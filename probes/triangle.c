/* triangle.c: milestone b. RADV (mesa-ps4, linked into the title) draws a green triangle on a black
 * clear through VK_EXT_headless_surface, which wsi_orbis.c turns into VideoOut flips, and the title
 * reports what DXVK 2.6.2 needs from the device:
 *
 *     PS4WINE b triangle frames=.. api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1
 *         build=<id> edyn3=.. desc_idx=.. ... gpu_hang=0 err=-
 *
 * on klog and netlog once frame 300 has been presented, then keeps presenting so the picture stays
 * up for shot.sh. Frame 300 is also copied back from its swapchain image and written, as the raw
 * bytes VideoOut scans out (A8B8G8R8: R first), to /data/ps4-wine/shot.raw for scripts/ps4/fbshot.sh;
 * fb=ok in the line says the file is this run's. An orange square at ORANGE_X,ORANGE_Y makes the
 * pixel check sensitive to a red/blue swap, which green alone is not. A Vulkan failure or a GPU hang emits the same line with err= set and idles, so
 * check.sh reads FAIL rather than NOLOG. The full extension list, the heaps and
 * maxMemoryAllocationSize go to netlog only (klog costs 8-15 ms a line). Never returns from main.
 *
 * From: orbis-ports/orbis-porting-kit examples/triangle/triangle.c @ 213b0c3 (MIT)
 *       (instance/headless surface/swapchain/render pass/pipeline/present sequence)
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stdarg.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <vulkan/vulkan.h>

#include "probe_sce.h"
#include "probe_util.h"
#include "triangle_caps.h"

#include "triangle_vert_spv.h"
#include "triangle_frag_spv.h"

#ifndef PROBE_BUILD_ID
#define PROBE_BUILD_ID "unknown"
#endif

#define REPORT_FRAME 300      /* about 5 s at 60 Hz */
#define FPS_FROM     60       /* the first second includes pipeline and WSI warm-up */
#define FENCE_NS     2000000000ull

/* The orange marker: a 64x64 square centred here, clear of the triangle (x 384..1536, y 216..864 at
 * 1920x1080). check.sh b expects 255,128,0 at this pixel; swapped red and blue read 0,128,255. */
#define ORANGE_X     240
#define ORANGE_Y     135
#define ORANGE_HALF  32

#define FB_DIR       "/data/ps4-wine"
#define FB_PATH      FB_DIR "/shot.raw"

static uint64_t t0_us;
static struct pr_results results;
static unsigned long frames;

/* netlog always; klog too when to_klog (startup, fatal and result lines only). */
static void say_to( int to_klog, const char *fmt, va_list ap )
{
    char buf[1024];
    int n = snprintf( buf, sizeof(buf), "[%8.3f] triangle: ", (double)(k_process_time() - t0_us) / 1e6 );
    n += vsnprintf( buf + n, sizeof(buf) - n - 2, fmt, ap );
    if (n > (int)sizeof(buf) - 2) n = sizeof(buf) - 2;
    buf[n++] = '\n';
    buf[n] = 0;
    probe_netlog_send( buf, n );
    if (to_klog) k_debug_out( 0, buf );
}

static void say( const char *fmt, ... ) __attribute__((format(printf, 1, 2)));
static void say( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 0, fmt, ap );
    va_end( ap );
}

static void say_k( const char *fmt, ... ) __attribute__((format(printf, 1, 2)));
static void say_k( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 1, fmt, ap );
    va_end( ap );
}

static void set_field( const char *key, const char *fmt, ... ) __attribute__((format(printf, 2, 3)));
static void set_field( const char *key, const char *fmt, ... )
{
    char val[PR_VAL_LEN];
    va_list ap;
    va_start( ap, fmt );
    vsnprintf( val, sizeof(val), fmt, ap );
    va_end( ap );
    if (pr_set( &results, key, val ) < 0) say( "field %s=%s not stored", key, val );
}

/* The result line exactly as check.sh greps it: no timestamp prefix. */
static void emit_line(void)
{
    char buf[1024];
    int n;

    set_field( "frames", "%lu", frames );
    n = tc_format_line( &results, PROBE_BUILD_ID, buf, sizeof(buf) - 1 );
    if (n < 0) n = snprintf( buf, sizeof(buf) - 1, "PS4WINE b triangle overflow frames=%lu", frames );
    buf[n++] = '\n';
    buf[n] = 0;
    probe_netlog_send( buf, n );
    k_debug_out( 0, buf );
}

static void __attribute__((noreturn)) idle_forever(void)
{
    for (;;) k_usleep( 1000 * 1000 );
}

/* Every call is checked and named: on this console a black screen has a dozen causes. */
static void must( VkResult r, const char *what )
{
    if (r == VK_SUCCESS) return;
    say_k( "FAILED at %s -> VkResult %d after %lu frame(s); idling", what, (int)r, frames );
    set_field( "err", "%s:%d", what, (int)r );
    emit_line();
    idle_forever();
}

/* ------------------------------------------------------------------ capability dump */
struct caps_chain
{
    VkPhysicalDeviceFeatures2 f2;
    VkPhysicalDeviceVulkan12Features v12;
    VkPhysicalDeviceVulkan13Features v13;
    VkPhysicalDeviceMaintenance5Features m5;
    VkPhysicalDeviceRobustness2FeaturesEXT rb2;
    VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT gpl;
    VkPhysicalDeviceTransformFeedbackFeaturesEXT xfb;
    VkPhysicalDeviceExtendedDynamicState3FeaturesEXT eds3;
    VkPhysicalDeviceCustomBorderColorFeaturesEXT cbc;
    VkPhysicalDeviceDepthClipEnableFeaturesEXT dce;
    VkPhysicalDeviceConditionalRenderingFeaturesEXT cr;
};

static void dump_caps( VkPhysicalDevice phys )
{
    VkPhysicalDeviceVulkan11Properties p11 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES };
    VkPhysicalDeviceProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &p11 };
    VkPhysicalDeviceMemoryProperties mem;
    static struct caps_chain c;
    VkExtensionProperties *ext;
    const char **names;
    uint32_t next_ext = 0, i;
    unsigned next = 0;
    char api[16], line[512];

    vkGetPhysicalDeviceProperties2( phys, &p2 );
    tc_api_string( p2.properties.apiVersion, api, sizeof(api) );
    set_field( "api", "%s", api );
    say_k( "device \"%s\" api %u.%u.%u driver 0x%08x vendor 0x%04x device 0x%04x", p2.properties.deviceName,
           VK_API_VERSION_MAJOR(p2.properties.apiVersion), VK_API_VERSION_MINOR(p2.properties.apiVersion),
           VK_API_VERSION_PATCH(p2.properties.apiVersion), p2.properties.driverVersion,
           p2.properties.vendorID, p2.properties.deviceID );
    set_field( "max_alloc_mib", "%llu", (unsigned long long)(p11.maxMemoryAllocationSize >> 20) );

    vkGetPhysicalDeviceMemoryProperties( phys, &mem );
    for (i = 0; i < mem.memoryHeapCount; i++)
        say( "heap %u: %llu MiB flags 0x%x", i, (unsigned long long)(mem.memoryHeaps[i].size >> 20),
             mem.memoryHeaps[i].flags );
    for (i = 0; i < mem.memoryTypeCount; i++)
        say( "memtype %u: heap %u flags 0x%x", i, mem.memoryTypes[i].heapIndex, mem.memoryTypes[i].propertyFlags );
    if (mem.memoryHeapCount) set_field( "heap0_mib", "%llu", (unsigned long long)(mem.memoryHeaps[0].size >> 20) );
    say( "maxMemoryAllocationSize %llu MiB", (unsigned long long)(p11.maxMemoryAllocationSize >> 20) );

    must( vkEnumerateDeviceExtensionProperties( phys, NULL, &next_ext, NULL ), "vkEnumerateDeviceExtensionProperties(count)" );
    ext = calloc( next_ext, sizeof(*ext) );
    names = calloc( next_ext, sizeof(*names) );
    must( vkEnumerateDeviceExtensionProperties( phys, NULL, &next_ext, ext ), "vkEnumerateDeviceExtensionProperties" );
    for (i = 0; i < next_ext; i++) names[i] = ext[i].extensionName;
    set_field( "exts", "%u", next_ext );
    say( "%u device extensions", next_ext );
    while (tc_pack_names( "ext", names, next_ext, &next, 480, line, sizeof(line) ) > 0) say( "%s", line );

    c.f2   = (VkPhysicalDeviceFeatures2){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &c.v12 };
    c.v12  = (VkPhysicalDeviceVulkan12Features){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &c.v13 };
    c.v13  = (VkPhysicalDeviceVulkan13Features){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .pNext = &c.m5 };
    c.m5   = (VkPhysicalDeviceMaintenance5Features){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES, .pNext = &c.rb2 };
    c.rb2  = (VkPhysicalDeviceRobustness2FeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT, .pNext = &c.gpl };
    c.gpl  = (VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT, .pNext = &c.xfb };
    c.xfb  = (VkPhysicalDeviceTransformFeedbackFeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_FEATURES_EXT, .pNext = &c.eds3 };
    c.eds3 = (VkPhysicalDeviceExtendedDynamicState3FeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT, .pNext = &c.cbc };
    c.cbc  = (VkPhysicalDeviceCustomBorderColorFeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CUSTOM_BORDER_COLOR_FEATURES_EXT, .pNext = &c.dce };
    c.dce  = (VkPhysicalDeviceDepthClipEnableFeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEPTH_CLIP_ENABLE_FEATURES_EXT, .pNext = &c.cr };
    c.cr   = (VkPhysicalDeviceConditionalRenderingFeaturesEXT){ .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_CONDITIONAL_RENDERING_FEATURES_EXT };
    vkGetPhysicalDeviceFeatures2( phys, &c.f2 );

#define HAS(e) tc_has_ext( names, next_ext, e )
    /* 1 = the extension is advertised and the feature DXVK uses from it is on. */
    set_field( "maintenance5", "%d", HAS("VK_KHR_maintenance5") && c.m5.maintenance5 );
    set_field( "robustness2", "%d", HAS("VK_EXT_robustness2") && c.rb2.robustBufferAccess2 && c.rb2.nullDescriptor );
    set_field( "gpl", "%d", HAS("VK_EXT_graphics_pipeline_library") && c.gpl.graphicsPipelineLibrary );
    set_field( "dyn_rendering", "%d", HAS("VK_KHR_dynamic_rendering") && c.v13.dynamicRendering );
    set_field( "xfb", "%d", HAS("VK_EXT_transform_feedback") && c.xfb.transformFeedback && c.xfb.geometryStreams );
    set_field( "edyn3", "%d", HAS("VK_EXT_extended_dynamic_state3") && c.eds3.extendedDynamicState3RasterizationSamples );
    set_field( "desc_idx", "%d", HAS("VK_EXT_descriptor_indexing") && c.v12.descriptorIndexing );
    set_field( "timeline", "%d", HAS("VK_KHR_timeline_semaphore") && c.v12.timelineSemaphore );
    set_field( "bda", "%d", HAS("VK_KHR_buffer_device_address") && c.v12.bufferDeviceAddress );
    set_field( "cbc", "%d", HAS("VK_EXT_custom_border_color") && c.cbc.customBorderColors && c.cbc.customBorderColorWithoutFormat );
    set_field( "dce", "%d", HAS("VK_EXT_depth_clip_enable") && c.dce.depthClipEnable );
    /* Hidden by patches/mesa-ps4/0001: anything but 0 means the patch is not in this driver. */
    set_field( "cond_render", "%d", HAS("VK_EXT_conditional_rendering") || c.cr.conditionalRendering );
    set_field( "indirect_count", "%d", HAS("VK_KHR_draw_indirect_count") || HAS("VK_AMD_draw_indirect_count") || c.v12.drawIndirectCount );
#undef HAS
    say( "features: robustBufferAccess2 %u robustImageAccess2 %u nullDescriptor %u, eds3 depthClipEnable %u, "
         "xfb geometryStreams %u, descriptorIndexing %u", c.rb2.robustBufferAccess2, c.rb2.robustImageAccess2,
         c.rb2.nullDescriptor, c.eds3.extendedDynamicState3DepthClipEnable, c.xfb.geometryStreams,
         c.v12.descriptorIndexing );
    free( names );
    free( ext );
}

/* ------------------------------------------------------------------ framebuffer readback */
struct readback
{
    VkDevice device;
    VkBuffer buf;
    VkDeviceMemory mem;
    void *map;
    VkCommandBuffer cmd;
};

/* A host-visible, coherent (cached when possible) buffer for one frame, tightly packed. Failures
 * are recorded in fb= and leave rb->cmd NULL: the readback is evidence, not the gate's frames. */
static void readback_init( struct readback *rb, VkPhysicalDevice phys, VkDevice device, VkCommandPool pool,
                           VkExtent2D extent )
{
    const VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    VkBufferCreateInfo bci = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = (VkDeviceSize)extent.width * extent.height * 4,
        .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    VkPhysicalDeviceMemoryProperties mp;
    VkMemoryRequirements req;
    uint32_t type = UINT32_MAX, i;
    VkResult r;

    rb->device = device;
    if ((r = vkCreateBuffer( device, &bci, NULL, &rb->buf )) != VK_SUCCESS) { set_field( "fb", "err:vkCreateBuffer:%d", r ); return; }
    vkGetBufferMemoryRequirements( device, rb->buf, &req );
    vkGetPhysicalDeviceMemoryProperties( phys, &mp );
    for (i = 0; i < mp.memoryTypeCount; i++)
    {
        VkMemoryPropertyFlags f = mp.memoryTypes[i].propertyFlags;
        if (!(req.memoryTypeBits & (1u << i)) || (f & want) != want) continue;
        if (type == UINT32_MAX || (f & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)) type = i;
        if (f & VK_MEMORY_PROPERTY_HOST_CACHED_BIT) break;
    }
    if (type == UINT32_MAX) { set_field( "fb", "err:no-host-memory" ); return; }
    VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = req.size, .memoryTypeIndex = type };
    if ((r = vkAllocateMemory( device, &mai, NULL, &rb->mem )) != VK_SUCCESS) { set_field( "fb", "err:vkAllocateMemory:%d", r ); return; }
    if ((r = vkBindBufferMemory( device, rb->buf, rb->mem, 0 )) != VK_SUCCESS) { set_field( "fb", "err:vkBindBufferMemory:%d", r ); return; }
    if ((r = vkMapMemory( device, rb->mem, 0, VK_WHOLE_SIZE, 0, &rb->map )) != VK_SUCCESS) { set_field( "fb", "err:vkMapMemory:%d", r ); return; }
    VkCommandBufferAllocateInfo cbai = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1,
    };
    if ((r = vkAllocateCommandBuffers( device, &cbai, &rb->cmd )) != VK_SUCCESS) { rb->cmd = VK_NULL_HANDLE; set_field( "fb", "err:vkAllocateCommandBuffers:%d", r ); return; }
    say( "readback buffer %llu bytes in memory type %u", (unsigned long long)req.size, type );
}

/* Submitted right after the frame's own commands, while the image is still ours (before the
 * present): PRESENT_SRC -> TRANSFER_SRC, copy, back to PRESENT_SRC, and make the copy host-visible. */
static void readback_record( struct readback *rb, VkImage image, VkExtent2D extent )
{
    VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    VkImageMemoryBarrier to_src = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
        .oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image, .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
    };
    VkImageMemoryBarrier to_present = to_src;
    VkBufferMemoryBarrier to_host = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = rb->buf, .offset = 0, .size = VK_WHOLE_SIZE,
    };
    VkBufferImageCopy region = {
        .bufferOffset = 0, .bufferRowLength = 0, .bufferImageHeight = 0,
        .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
        .imageExtent = { extent.width, extent.height, 1 },
    };

    to_present.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    to_present.dstAccessMask = 0;
    to_present.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    to_present.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    must( vkBeginCommandBuffer( rb->cmd, &bi ), "vkBeginCommandBuffer(readback)" );
    vkCmdPipelineBarrier( rb->cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                          0, 0, NULL, 0, NULL, 1, &to_src );
    vkCmdCopyImageToBuffer( rb->cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, rb->buf, 1, &region );
    vkCmdPipelineBarrier( rb->cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT | VK_PIPELINE_STAGE_HOST_BIT,
                          0, 0, NULL, 1, &to_host, 1, &to_present );
    must( vkEndCommandBuffer( rb->cmd ), "vkEndCommandBuffer(readback)" );
}

static void say_pixel( const uint8_t *px, uint32_t width, uint32_t x, uint32_t y, const char *what )
{
    const uint8_t *p = px + ((size_t)y * width + x) * 4;
    say( "fb pixel %u,%u (%s): bytes %u,%u,%u,%u", x, y, what, p[0], p[1], p[2], p[3] );
}

/* After the frame's fence: the bytes as the copy left them (the swapchain format's byte order; the
 * scan-out reads them as R,G,B,A), to FB_PATH via a temporary name so a partial file is never fetched. */
static void readback_save( struct readback *rb, VkExtent2D extent )
{
    const size_t len = (size_t)extent.width * extent.height * 4;
    const uint64_t t = k_process_time();
    FILE *f;
    size_t n;

    say_pixel( rb->map, extent.width, extent.width / 2, extent.height / 2, "centre" );
    say_pixel( rb->map, extent.width, ORANGE_X, ORANGE_Y, "orange" );
    if (!(f = fopen( FB_PATH ".tmp", "wb" ))) { set_field( "fb", "err:open" ); return; }
    n = fwrite( rb->map, 1, len, f );
    fflush( f );
    fsync( fileno( f ) );
    fclose( f );
    if (n != len) { set_field( "fb", "err:short-write:%zu", n ); return; }
    if (rename( FB_PATH ".tmp", FB_PATH ) != 0) { set_field( "fb", "err:rename" ); return; }
    set_field( "fb", "ok" );
    say( "wrote %s: %ux%u, %zu bytes in %.0f ms", FB_PATH, extent.width, extent.height, len,
         (double)(k_process_time() - t) / 1e3 );
}

int main( int argc, char **argv )
{
    (void)argc; (void)argv;
    t0_us = k_process_time();
    pr_init( &results );
    set_field( "gpu_hang", "0" );
    set_field( "err", "-" );
    probe_netlog_init();
    /* A stale shot from an earlier run must never be fetched as this run's. */
    mkdir( FB_DIR, 0777 );
    unlink( FB_PATH );
    set_field( "fb", "none" );
    say_k( "PS4WINE triangle start build=%s netlog=%s:%d", PROBE_BUILD_ID, PROBE_NETLOG_HOST, PROBE_NETLOG_PORT );

    /* ---------------------------------------------------------------- instance */
    const char *inst_ext[] = { "VK_KHR_surface", "VK_EXT_headless_surface" };
    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "ps4-wine triangle",
        .apiVersion = VK_API_VERSION_1_3,
    };
    VkInstanceCreateInfo ici = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
        .enabledExtensionCount = 2,
        .ppEnabledExtensionNames = inst_ext,
    };
    VkInstance instance;
    must( vkCreateInstance( &ici, NULL, &instance ), "vkCreateInstance" );

    VkHeadlessSurfaceCreateInfoEXT hsci = { .sType = VK_STRUCTURE_TYPE_HEADLESS_SURFACE_CREATE_INFO_EXT };
    VkSurfaceKHR surface;
    must( vkCreateHeadlessSurfaceEXT( instance, &hsci, NULL, &surface ), "vkCreateHeadlessSurfaceEXT" );

    /* ---------------------------------------------------------------- device */
    uint32_t ndev = 1;
    VkPhysicalDevice phys;
    VkResult er = vkEnumeratePhysicalDevices( instance, &ndev, &phys );
    if (er == VK_INCOMPLETE) er = VK_SUCCESS;
    must( er, "vkEnumeratePhysicalDevices" );
    if (ndev == 0) must( VK_ERROR_INITIALIZATION_FAILED, "no-physical-device" );

    dump_caps( phys );

    uint32_t nqf = 0, qf = UINT32_MAX;
    vkGetPhysicalDeviceQueueFamilyProperties( phys, &nqf, NULL );
    VkQueueFamilyProperties *qfp = calloc( nqf, sizeof(*qfp) );
    vkGetPhysicalDeviceQueueFamilyProperties( phys, &nqf, qfp );
    for (uint32_t i = 0; i < nqf && qf == UINT32_MAX; i++)
    {
        VkBool32 present = VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR( phys, i, surface, &present );
        if ((qfp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present) qf = i;
    }
    free( qfp );
    if (qf == UINT32_MAX) must( VK_ERROR_INITIALIZATION_FAILED, "no-present-queue" );

    const float prio = 1.0f;
    const char *dev_ext[] = { "VK_KHR_swapchain" };
    VkDeviceQueueCreateInfo qci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = qf, .queueCount = 1, .pQueuePriorities = &prio,
    };
    VkDeviceCreateInfo dci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci,
        .enabledExtensionCount = 1, .ppEnabledExtensionNames = dev_ext,
    };
    VkDevice device;
    must( vkCreateDevice( phys, &dci, NULL, &device ), "vkCreateDevice" );
    VkQueue queue;
    vkGetDeviceQueue( device, qf, 0, &queue );

    /* ---------------------------------------------------------------- swapchain */
    VkSurfaceCapabilitiesKHR caps;
    must( vkGetPhysicalDeviceSurfaceCapabilitiesKHR( phys, surface, &caps ), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR" );
    uint32_t nfmt = 0;
    must( vkGetPhysicalDeviceSurfaceFormatsKHR( phys, surface, &nfmt, NULL ), "vkGetPhysicalDeviceSurfaceFormatsKHR(count)" );
    if (nfmt == 0) must( VK_ERROR_FORMAT_NOT_SUPPORTED, "no-surface-format" );
    VkSurfaceFormatKHR *fmts = calloc( nfmt, sizeof(*fmts) );
    must( vkGetPhysicalDeviceSurfaceFormatsKHR( phys, surface, &nfmt, fmts ), "vkGetPhysicalDeviceSurfaceFormatsKHR" );
    for (uint32_t i = 0; i < nfmt; i++) say( "surface format %u: %d colourspace %d", i, fmts[i].format, fmts[i].colorSpace );
    const VkSurfaceFormatKHR fmt = fmts[0];   /* RGBA only on this driver; green survives a swap anyway */
    free( fmts );

    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX) { extent.width = 1920; extent.height = 1080; }
    set_field( "swapchain", "%ux%u", extent.width, extent.height );
    set_field( "fmt", "%d", (int)fmt.format );
    say( "surface %ux%u, %u..%u images, usage 0x%x", extent.width, extent.height, caps.minImageCount,
         caps.maxImageCount, caps.supportedUsageFlags );
    const int can_read = !!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
    if (!can_read) set_field( "fb", "no-transfer-src" );

    VkSwapchainCreateInfoKHR sci = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = caps.minImageCount < 2 ? 2 : caps.minImageCount,
        .imageFormat = fmt.format, .imageColorSpace = fmt.colorSpace,
        .imageExtent = extent, .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | (can_read ? VK_IMAGE_USAGE_TRANSFER_SRC_BIT : 0),
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR,
        .clipped = VK_TRUE,
    };
    VkSwapchainKHR swapchain;
    must( vkCreateSwapchainKHR( device, &sci, NULL, &swapchain ), "vkCreateSwapchainKHR" );
    uint32_t nimg = 0;
    must( vkGetSwapchainImagesKHR( device, swapchain, &nimg, NULL ), "vkGetSwapchainImagesKHR(count)" );
    VkImage *images = calloc( nimg, sizeof(*images) );
    must( vkGetSwapchainImagesKHR( device, swapchain, &nimg, images ), "vkGetSwapchainImagesKHR" );
    say( "swapchain has %u images", nimg );

    /* ---------------------------------------------------------------- render pass, framebuffers */
    VkAttachmentDescription att = {
        .format = fmt.format, .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE, .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED, .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    VkAttachmentReference ref = { .attachment = 0, .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkSubpassDescription sub = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS, .colorAttachmentCount = 1, .pColorAttachments = &ref,
    };
    VkRenderPassCreateInfo rpci = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &att, .subpassCount = 1, .pSubpasses = &sub,
    };
    VkRenderPass rp;
    must( vkCreateRenderPass( device, &rpci, NULL, &rp ), "vkCreateRenderPass" );

    VkImageView *views = calloc( nimg, sizeof(*views) );
    VkFramebuffer *fbs = calloc( nimg, sizeof(*fbs) );
    for (uint32_t i = 0; i < nimg; i++)
    {
        VkImageViewCreateInfo ivci = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images[i], .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = fmt.format,
            .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
        };
        must( vkCreateImageView( device, &ivci, NULL, &views[i] ), "vkCreateImageView" );
        VkFramebufferCreateInfo fci = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = rp, .attachmentCount = 1, .pAttachments = &views[i],
            .width = extent.width, .height = extent.height, .layers = 1,
        };
        must( vkCreateFramebuffer( device, &fci, NULL, &fbs[i] ), "vkCreateFramebuffer" );
    }

    /* ---------------------------------------------------------------- pipeline */
    VkShaderModuleCreateInfo vsci = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = sizeof(triangle_vert_spv), .pCode = triangle_vert_spv,
    };
    VkShaderModuleCreateInfo fsci = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = sizeof(triangle_frag_spv), .pCode = triangle_frag_spv,
    };
    VkShaderModule vs, fs;
    must( vkCreateShaderModule( device, &vsci, NULL, &vs ), "vkCreateShaderModule(vert)" );
    must( vkCreateShaderModule( device, &fsci, NULL, &fs ), "vkCreateShaderModule(frag)" );
    VkPipelineShaderStageCreateInfo stages[2] = {
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = vs, .pName = "main" },
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = fs, .pName = "main" },
    };
    VkPipelineVertexInputStateCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    VkPipelineInputAssemblyStateCreateInfo ia = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkViewport vp = { 0, 0, (float)extent.width, (float)extent.height, 0.0f, 1.0f };
    VkRect2D sc = { { 0, 0 }, extent };
    VkPipelineViewportStateCreateInfo vps = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .pViewports = &vp, .scissorCount = 1, .pScissors = &sc,
    };
    VkPipelineRasterizationStateCreateInfo rs = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo ms = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    VkPipelineColorBlendAttachmentState cba = { .colorWriteMask = 0xf };
    VkPipelineColorBlendStateCreateInfo cb = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &cba,
    };
    VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    VkPipelineLayout layout;
    must( vkCreatePipelineLayout( device, &plci, NULL, &layout ), "vkCreatePipelineLayout" );
    VkGraphicsPipelineCreateInfo gpci = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages,
        .pVertexInputState = &vi, .pInputAssemblyState = &ia, .pViewportState = &vps,
        .pRasterizationState = &rs, .pMultisampleState = &ms, .pColorBlendState = &cb,
        .layout = layout, .renderPass = rp, .subpass = 0,
    };
    VkPipeline pipeline;
    must( vkCreateGraphicsPipelines( device, VK_NULL_HANDLE, 1, &gpci, NULL, &pipeline ), "vkCreateGraphicsPipelines" );

    /* ---------------------------------------------------------------- commands */
    VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = qf };
    VkCommandPool pool;
    must( vkCreateCommandPool( device, &cpci, NULL, &pool ), "vkCreateCommandPool" );
    VkCommandBuffer *cmds = calloc( nimg, sizeof(*cmds) );
    VkCommandBufferAllocateInfo cbai = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = nimg,
    };
    must( vkAllocateCommandBuffers( device, &cbai, cmds ), "vkAllocateCommandBuffers" );
    for (uint32_t i = 0; i < nimg; i++)
    {
        VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        VkClearValue clear = { .color = { .float32 = { 0.0f, 0.0f, 0.0f, 1.0f } } };
        VkRenderPassBeginInfo rpbi = {
            .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = rp, .framebuffer = fbs[i], .renderArea = { { 0, 0 }, extent },
            .clearValueCount = 1, .pClearValues = &clear,
        };
        must( vkBeginCommandBuffer( cmds[i], &bi ), "vkBeginCommandBuffer" );
        vkCmdBeginRenderPass( cmds[i], &rpbi, VK_SUBPASS_CONTENTS_INLINE );
        vkCmdBindPipeline( cmds[i], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline );
        vkCmdDraw( cmds[i], 3, 1, 0, 0 );
        VkClearAttachment orange = {
            .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT, .colorAttachment = 0,
            .clearValue = { .color = { .float32 = { 1.0f, 0.5f, 0.0f, 1.0f } } },
        };
        VkClearRect orange_rect = {
            .rect = { { ORANGE_X - ORANGE_HALF, ORANGE_Y - ORANGE_HALF }, { 2 * ORANGE_HALF, 2 * ORANGE_HALF } },
            .baseArrayLayer = 0, .layerCount = 1,
        };
        vkCmdClearAttachments( cmds[i], 1, &orange, 1, &orange_rect );
        vkCmdEndRenderPass( cmds[i] );
        must( vkEndCommandBuffer( cmds[i] ), "vkEndCommandBuffer" );
    }

    VkSemaphoreCreateInfo semci = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkSemaphore acquired, rendered;
    VkFence done;
    must( vkCreateSemaphore( device, &semci, NULL, &acquired ), "vkCreateSemaphore(acquired)" );
    must( vkCreateSemaphore( device, &semci, NULL, &rendered ), "vkCreateSemaphore(rendered)" );
    must( vkCreateFence( device, &fci, NULL, &done ), "vkCreateFence" );

    struct readback rb = { 0 };
    if (can_read) readback_init( &rb, phys, device, pool, extent );

    /* ---------------------------------------------------------------- present, forever */
    say_k( "setup complete, presenting" );
    uint64_t t_from = 0;
    for (;;)
    {
        uint32_t idx = 0;
        VkResult r = vkAcquireNextImageKHR( device, swapchain, FENCE_NS, acquired, VK_NULL_HANDLE, &idx );
        if (r == VK_SUBOPTIMAL_KHR) r = VK_SUCCESS;
        must( r, "vkAcquireNextImageKHR" );
        VkPipelineStageFlags wait = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        const int read_now = rb.cmd && frames + 1 == REPORT_FRAME;
        VkCommandBuffer frame_cmds[2] = { cmds[idx], rb.cmd };
        if (read_now) readback_record( &rb, images[idx], extent );
        VkSubmitInfo si = {
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1, .pWaitSemaphores = &acquired, .pWaitDstStageMask = &wait,
            .commandBufferCount = read_now ? 2 : 1, .pCommandBuffers = frame_cmds,
            .signalSemaphoreCount = 1, .pSignalSemaphores = &rendered,
        };
        must( vkQueueSubmit( queue, 1, &si, done ), "vkQueueSubmit" );
        VkPresentInfoKHR pi = {
            .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1, .pWaitSemaphores = &rendered,
            .swapchainCount = 1, .pSwapchains = &swapchain, .pImageIndices = &idx,
        };
        r = vkQueuePresentKHR( queue, &pi );
        if (r == VK_SUBOPTIMAL_KHR) r = VK_SUCCESS;
        must( r, "vkQueuePresentKHR" );
        /* A fence with a timeout rather than vkQueueWaitIdle, so a hung GPU is a FAIL line and not silence. */
        r = vkWaitForFences( device, 1, &done, VK_TRUE, FENCE_NS );
        if (r == VK_TIMEOUT) set_field( "gpu_hang", "1" );
        must( r, "vkWaitForFences" );
        must( vkResetFences( device, 1, &done ), "vkResetFences" );
        must( vkQueueWaitIdle( queue ), "vkQueueWaitIdle" );
        frames++;

        if (frames == FPS_FROM) t_from = k_process_time();
        if (frames == REPORT_FRAME)
        {
            uint64_t dt = k_process_time() - t_from;
            set_field( "fps", "%.1f", dt ? (double)(REPORT_FRAME - FPS_FROM) * 1e6 / (double)dt : 0.0 );
            if (rb.cmd) readback_save( &rb, extent );
            emit_line();
        }
        else if ((frames & (frames - 1)) == 0 || (frames & 1023) == 0) say( "alive frames=%lu", frames );
    }
}

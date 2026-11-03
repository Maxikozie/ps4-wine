/* lowbase_prx.c: milestone i1's probe, the part that runs in lowbase.prx (docs/ps4/HANDOFF-i.md,
 * "i1, the probe", stages 1-15). The stub eboot (stub.c) calls lowbase_main on the main thread.
 * The stages open VideoOut, release every segment of module 0 (the eboot at 0x400000) with the
 * fork's pw_eboot_release, take 0x400000 back the way Wine's reserve and direct-memory paths do,
 * then exercise what a Wine session needs afterwards, each stage under a guard, and finally keep
 * the process alive for 600 s with sceGnmSubmitDone on every tick before printing
 *     PS4WINE i1 lowbase direct_mib=... release=... ... launches=N build=<id>
 * on klog, netlog and LB_LOG. The tick goes on afterwards; a suspend (the user's Home and back) is
 * recorded as a PW_MS stage=suspend record, never in the line.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "lowbase.h"
#include "probe_sce.h"
#include "probe_util.h"
#include "pw_eboot_release.h"

#include <errno.h>
#include <locale.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef PROBE_BUILD_ID
#define PROBE_BUILD_ID "unknown"
#endif

#define LOW_BASE      ((uintptr_t)0x400000)
#define LOW_BYTES     ((size_t)0x40c000)      /* Psychonauts.exe's SizeOfImage, a 16 KiB multiple */
#define K_MAP_NO_OVERWRITE 0x0080
#define ALIVE_S       600
#define TICK_US       100000
#define SYSMODULE_KEYBOARD 0x0106

/* lowbase.prx's own thread-local, .tbss: its offset lands in the stub's PT_TLS block. */
__thread uint64_t lb_tls;

static int32_t user_id = -1;
static uintptr_t eboot_lo, eboot_hi;

/* ------------------------------------------------------------------ watchdog */
static volatile uint64_t deadline_us;
static const char *volatile cur_stage = "start";

static void *watchdog( void *arg )
{
    (void)arg;
    for (;;)
    {
        uint64_t d = deadline_us;
        k_usleep( 500 * 1000 );
        if (d && d == deadline_us && lb_now_us() > d)
        {
            lb_say_k( "!! HANG: stage %s ran past its deadline; the next launch records it as crash", cur_stage );
            k_usleep( 300 * 1000 );
            _exit( 3 );
        }
    }
    return NULL;
}

/* ------------------------------------------------------------------ stages */
/* 1. the direct-memory grant with a stub eboot and three PRXs in sce_module/ */
static void st_direct(void)
{
    lb_set( "direct_mib", "%llu", (unsigned long long)(k_direct_size() >> 20) );
}

/* 2. VideoOut open #1 before the release, one green flip */
static void st_vo1(void)
{
    int rc = 0;
    if (!lb_screen_open( &rc )) { lb_set_rc( "vo1", rc ? rc : -1 ); return; }
    rc = lb_screen_show( LB_GREEN );
    if (rc >= 0) lb_set( "vo1", "ok" );
    else lb_set( "vo1", "flip:0x%08x", (unsigned)rc );
}

/* 3. the release: a reserve of the PE range first (the eboot holds it: refused), then every
 * segment of module 0 unmapped */
static int eboot_info( void *context, void *info ) { (void)context; return k_module_info( 0, info ); }
static int eboot_unmap( void *context, void *address, size_t bytes ) { (void)context; return k_munmap( address, bytes ); }

static PwEbootRelease released;   /* i1b reads the segments */

static void st_release(void)
{
    PwEbootReleaseOps ops = { eboot_info, eboot_unmap, NULL };
    PwEbootRelease r;
    void *want = (void *)LOW_BASE;
    int rc;

    rc = k_reserve( &want, LOW_BYTES, K_MAP_FIXED | K_MAP_NO_OVERWRITE, K_GRANULE );
    if (!rc) { lb_set( "pre_reserve", "free" ); k_munmap( want, LOW_BYTES ); }
    else lb_set( "pre_reserve", "err:0x%08x", (unsigned)rc );

    rc = pw_eboot_release( &ops, &r );
    for (uint32_t i = 0; i < r.segment_count; i++)
        lb_say( "  eboot seg%u %p size=0x%x prot=0x%x", i, r.segments[i].address, r.segments[i].size,
                r.segments[i].protection );
    for (uint32_t i = 0; i < r.range_count; i++)
        lb_say( "  range%u 0x%lx-0x%lx %s", i, (unsigned long)r.ranges[i].base, (unsigned long)r.ranges[i].end,
                i < r.unmapped ? "unmapped" : "kept" );
    lb_set( "segs", "%u", r.segment_count );
    lb_set( "low_end", "0x%lx", (unsigned long)r.low_end );
    if (r.after == PW_EBOOT_AFTER_LISTED) lb_set( "module0_after", "listed:%u", r.after_count );
    else if (r.after == PW_EBOOT_AFTER_ERR) lb_set( "module0_after", "err:0x%08x", (unsigned)r.after_rc );
    else lb_set( "module0_after", "%s", pw_eboot_release_after_name( r.after ) );
    eboot_lo = r.low_base;
    eboot_hi = r.low_end;
    released = r;
    switch (rc)
    {
    case PW_EBOOT_OK: lb_set( "release", "ok" ); break;
    case PW_EBOOT_ERR_UNMAP: lb_set( "release", "err:0x%08x", (unsigned)r.unmap_rc ); break;
    case PW_EBOOT_ERR_MODULE_INFO: lb_set( "release", "modinfo:0x%08x", (unsigned)r.info_rc ); break;
    case PW_EBOOT_ERR_RANGE: lb_set( "release", "range" ); break;
    default: lb_set( "release", "err:%d", rc ); break;
    }
}

/* 4. the PE range, reserved FIXED|NO_OVERWRITE as Wine's anon_mmap_tryfixed does */
static void *low_reserved;

static void st_reserve400(void)
{
    void *want = (void *)LOW_BASE;
    int rc = k_reserve( &want, LOW_BYTES, K_MAP_FIXED | K_MAP_NO_OVERWRITE, K_GRANULE );

    if (rc) lb_set( "reserve400", "err:0x%08x", (unsigned)rc );
    else if (want != (void *)LOW_BASE) lb_set( "reserve400", "moved:%p", want );
    else { low_reserved = want; lb_set( "reserve400", "ok" ); }
}

/* 5. direct memory over the reservation (pw_wine_dmem_ps5.c's order: allocate, map FIXED RW,
 * mprotect), code at 0x401000 in a 16 KiB page made RX, called */
static void st_exec400(void)
{
    static const uint32_t marker = 0x1b400001u;
    void *at = (void *)LOW_BASE;
    uint8_t *code = (uint8_t *)LOW_BASE + 0x1000;
    off_t phys = 0;
    uint32_t got;
    int rc;

    if (!low_reserved) { lb_set( "exec400", "noreserve" ); return; }
    rc = k_alloc_direct( 0, (off_t)k_direct_size(), LOW_BYTES, K_GRANULE, K_WB_ONION, &phys );
    if (rc) { lb_set( "exec400", "alloc:0x%08x", (unsigned)rc ); return; }
    rc = k_map_direct( &at, LOW_BYTES, K_PROT_RW, K_MAP_FIXED, phys, K_GRANULE );
    if (rc || at != (void *)LOW_BASE) { lb_set( "exec400", "map:0x%08x", (unsigned)rc ); return; }
    memset( (uint8_t *)LOW_BASE + LOW_BYTES - 0x4000, 0x5a, 0x4000 );   /* the top page is writable */
    code[0] = 0xB8;                     /* mov eax, imm32 */
    memcpy( code + 1, &marker, 4 );
    code[5] = 0xC3;                     /* ret */
    rc = k_mprotect( (void *)LOW_BASE, K_GRANULE, K_PROT_RX );
    if (rc) { lb_set( "exec400", "mprotect:0x%08x", (unsigned)rc ); return; }
    got = ((uint32_t (*)(void))code)();
    lb_say( "  code at %p returned 0x%08x", (void *)code, got );
    if (got == marker) lb_set( "exec400", "ok" );
    else lb_set( "exec400", "wrong:0x%08x", got );
}

/* 6. VideoOut: close #1, open #2, a blue flip (the HDMI evidence) */
static void st_vo2(void)
{
    int rc = lb_screen_close();

    lb_set_rc( "vo1_close", rc );
    if (!lb_screen_open( &rc )) { lb_set( "vo2", "open:0x%08x", (unsigned)rc ); return; }
    rc = lb_screen_show( LB_BLUE );
    if (rc < 0) { lb_set( "vo2", "flip:0x%08x", (unsigned)rc ); return; }
    lb_set( "vo2", "ok" );
}

/* 7. the first sysmodule load after the release, and the keyboard opened through it (as the
 * fork's pw_hid_ps5.c: the system's module handle, then sceKernelDlsym) */
static void st_sysmod(void)
{
    int (*init)(void) = NULL;
    int (*open)( int32_t, int32_t, int32_t, void * ) = NULL;
    uint8_t param[8] = { 0 };
    int32_t module = -1;
    int rc = sceSysmoduleLoadModule( SYSMODULE_KEYBOARD ), handle;

    lb_set_rc( "sysmod", rc );
    if (sceSysmoduleGetModuleHandleInternal( SYSMODULE_KEYBOARD, &module ) || module < 0)
        sceSysmoduleGetModuleHandleInternal( 0x80000000u | SYSMODULE_KEYBOARD, &module );
    if (module < 0) { lb_set( "kbd_open", "nomodule" ); return; }
    if (k_dlsym( module, "sceKeyboardInit", (void **)&init ) || k_dlsym( module, "sceKeyboardOpen", (void **)&open ))
    {
        lb_set( "kbd_open", "nosym" );
        return;
    }
    rc = init();
    handle = open( user_id, 0, 0, param );
    lb_say( "  keyboard init 0x%08x open 0x%08x user %d", (unsigned)rc, (unsigned)handle, (int)user_id );
    if (handle >= 0) lb_set( "kbd_open", "ok" );
    else lb_set( "kbd_open", "err:0x%08x", (unsigned)handle );
}

/* 8. the pad */
static void st_pad(void)
{
    uint8_t state[512];
    int rc = scePadInit(), handle;

    handle = scePadOpen( user_id, 0, 0, NULL );
    if (handle < 0) { lb_set( "pad", "open:0x%08x", (unsigned)handle ); return; }
    rc = scePadReadState( handle, state );
    lb_set_rc( "pad", rc );
}

/* 9. app PRXs loaded after the release: module info, descriptor, module_start, dlsym */
static int load_prx( const char *path, const char *field, uint32_t (**value)( uint32_t ), int32_t *handle_out )
{
    uint8_t info[PW_PRX_MODULE_INFO_BYTES];
    uint64_t size_word = sizeof(info);
    PwPrxSegment segments[PW_PRX_MAX_SEGMENTS];
    const PwPrxDescriptor *desc = NULL;
    int (*module_start)( size_t, const void * );
    void *by_dlsym = NULL;
    uint32_t count = 0;
    int result = 0, handle, rc;

    handle = k_load_start_module( path, 0, NULL, 0, NULL, &result );
    lb_say( "  %s: load 0x%08x result %d", path, (unsigned)handle, result );
    if (handle < 0) { lb_set( field, "load:0x%08x", (unsigned)handle ); return 0; }
    memset( info, 0, sizeof(info) );
    memcpy( info, &size_word, sizeof(size_word) );
    rc = k_module_info( handle, info );
    memcpy( info, &size_word, sizeof(size_word) );
    if (rc || pw_prx_parse_module_info( info, NULL, segments, &count ) != PW_PRX_OK ||
        pw_prx_find_descriptor( segments, count, &desc ) != PW_PRX_OK)
    {
        lb_set( field, "desc:0x%08x", (unsigned)rc );
        return 0;
    }
    module_start = (int (*)( size_t, const void * ))pw_prx_lookup( desc, "module_start" );
    *value = (uint32_t (*)( uint32_t ))pw_prx_lookup( desc, "lowbase_mod_value" );
    if (!module_start || !*value) { lb_set( field, "nosym" ); return 0; }
    if ((rc = module_start( 0, NULL ))) { lb_set( field, "start:%d", rc ); return 0; }
    rc = k_dlsym( handle, "lowbase_mod_value", &by_dlsym );
    if (rc || by_dlsym != (void *)*value)
    {
        lb_set( field, "dlsym:0x%08x", (unsigned)rc );
        return 0;
    }
    *handle_out = handle;
    return 1;
}

static void st_prx(void)
{
    uint32_t (*value)( uint32_t ) = NULL;
    int (*tick_fn)( uint64_t * ) = NULL;
    uint64_t tick = 0;
    int32_t handle = -1;
    int rc;

    if (load_prx( "/app0/sce_module/lowbase_mod.prx", "prx", &value, &handle ))
        lb_set( "prx", value( 0x12345678u ) == (0x12345678u ^ 0xA5A5A5A5u) ? "ok" : "wrong" );

    /* Recorded only: a PRX that NEEDs libSceRtc, which nothing else here loads. */
    if (!load_prx( "/app0/sce_module/lowbase_mod2.prx", "prx_sce", &value, &handle )) return;
    rc = k_dlsym( handle, "lowbase_mod2_tick", (void **)&tick_fn );
    if (rc || !tick_fn) { lb_set( "prx_sce", "dlsym:0x%08x", (unsigned)rc ); return; }
    rc = tick_fn( &tick );
    lb_say( "  sceRtcGetCurrentTick 0x%08x tick %llu", (unsigned)rc, (unsigned long long)tick );
    if (rc || !tick) lb_set( "prx_sce", "rtc:0x%08x", (unsigned)rc );
    else lb_set( "prx_sce", "ok" );
}

/* 10. threads and thread-locals: 8 threads through orbis-compat's pthread_create (ntdll's path),
 * each with lowbase.prx's own __thread and musl's thread-local current locale */
#define N_THREADS 8
struct tls_check { int index; int zero_at_start; int own_value; int own_locale; };
static locale_t loc_c, loc_utf8;

static void *tls_thread( void *arg )
{
    struct tls_check *c = arg;
    uint64_t mine = 0x1b000000u + (uint64_t)c->index;
    locale_t want = (c->index & 1) ? loc_utf8 : loc_c;

    c->zero_at_start = lb_tls == 0 && uselocale( (locale_t)0 ) == LC_GLOBAL_LOCALE;
    lb_tls = mine;
    uselocale( want );
    k_usleep( 20 * 1000 );              /* let the other threads write theirs */
    c->own_value = lb_tls == mine;
    c->own_locale = uselocale( (locale_t)0 ) == want;
    return NULL;
}

static void st_threads(void)
{
    struct tls_check checks[N_THREADS];
    pthread_t threads[N_THREADS];
    int created = 0, joined = 0, bad = 0;

    loc_c = newlocale( LC_ALL_MASK, "C", (locale_t)0 );
    loc_utf8 = newlocale( LC_ALL_MASK, "C.UTF-8", (locale_t)0 );
    lb_tls = 0xA1A1u;
    for (int i = 0; i < N_THREADS; i++)
    {
        memset( &checks[i], 0, sizeof(checks[i]) );
        checks[i].index = i;
        if (!pthread_create( &threads[i], NULL, tls_thread, &checks[i] )) created++;
        else break;
    }
    for (int i = 0; i < created; i++)
        if (!pthread_join( threads[i], NULL )) joined++;
    for (int i = 0; i < created; i++)
        if (!checks[i].zero_at_start || !checks[i].own_value || !checks[i].own_locale) bad |= 1 << i;
    lb_say( "  threads created %d joined %d; locales C=%p C.UTF-8=%p; bad mask 0x%x", created, joined, (void *)loc_c,
            (void *)loc_utf8, (unsigned)bad );
    if (created == N_THREADS && joined == N_THREADS) lb_set( "threads", "ok" );
    else lb_set( "threads", "made:%d/%d", created, joined );
    if (lb_tls != 0xA1A1u || uselocale( (locale_t)0 ) != LC_GLOBAL_LOCALE) lb_set( "tls", "main_changed" );
    else if (!loc_c || !loc_utf8 || loc_c == loc_utf8) lb_set( "tls", "nolocale" );
    else if (created != N_THREADS) lb_set( "tls", "nothreads" );
    else if (bad) lb_set( "tls", "bad:0x%x", (unsigned)bad );
    else lb_set( "tls", "ok" );
}

/* 11. C++ throw/catch on the main thread and on a new one; a backtrace from the main thread,
 * whose stack runs through the released stub's frames */
static void *throw_thread( void *arg )
{
    *(int *)arg = lb_unwind_throw();
    return NULL;
}

static void st_unwind(void)
{
    pthread_t t;
    int main_ok = lb_unwind_throw(), thread_ok = 0, frames = 0, in_eboot = 0, rc = 0;

    if (!pthread_create( &t, NULL, throw_thread, &thread_ok )) pthread_join( t, NULL );
    lb_unwind_backtrace( eboot_lo, eboot_hi, &frames, &in_eboot, &rc );
    lb_say( "  throw main %d thread %d; backtrace rc %d frames %d in the released range %d", main_ok, thread_ok, rc,
            frames, in_eboot );
    lb_set( "unwind_frames", "%d", frames );
    lb_set( "unwind_eboot", "%d", in_eboot );
    if (main_ok && thread_ok) lb_set( "unwind", "ok" );
    else lb_set( "unwind", "throw:%d/%d", main_ok, thread_ok );
}

/* 12. a SEGV caught by FreeBSD sigaction installed after the release, resumed by moving rip */
extern uint64_t lb_load( const void *addr );
extern char lb_load_resume[];
__asm__(
    ".text\n"
    ".globl lb_load\n"
    "lb_load:\n"
    "    movl $0x1111, %eax\n"
    "    movq (%rdi), %rax\n"
    ".globl lb_load_resume\n"
    "lb_load_resume:\n"
    "    ret\n" );

static volatile int sa_hits;
static volatile uint64_t sa_addr;

static void fault_handler( int sig, void *info, void *uc )
{
    uint8_t *mc = (uint8_t *)uc + 64;   /* frame_mc=64, probe a */
    (void)sig; (void)info;
    sa_hits++;
    sa_addr = *(uint64_t *)(mc + PR_MC_ADDR);
    *(uint64_t *)(mc + PR_MC_RIP) = (uint64_t)(uintptr_t)lb_load_resume;
    *(uint64_t *)(mc + PR_MC_RAX) = 0xFA57;
}

static void st_fault(void)
{
    struct bsd_sigaction act, old;
    uint64_t got = 0;
    int rc;

    k_remove_exc( BSD_SIGSEGV );
    memset( &act, 0, sizeof(act) );
    act.handler = fault_handler;
    act.flags = BSD_SA_SIGINFO | BSD_SA_NODEFER;
    sa_hits = 0;
    rc = k_sigaction( BSD_SIGSEGV, &act, &old );
    if (!rc) got = lb_load( (const void *)0x10 );
    if (!rc) k_sigaction( BSD_SIGSEGV, &old, NULL );
    lb_guard_install();
    lb_say( "  sigaction rc %d, load returned 0x%lx, hits %d, address 0x%lx", rc, (unsigned long)got, sa_hits,
            (unsigned long)sa_addr );
    if (rc) lb_set( "fault", "sigaction:%d", rc );
    else if (got == 0xFA57 && sa_hits == 1) lb_set( "fault", "ok" );
    else lb_set( "fault", "wrong:%d", sa_hits );
}

/* 13. one AudioOut grain */
static void st_audio(void)
{
    static int16_t silence[256 * 2];
    int rc = sceAudioOutInit(), port;

    lb_say( "  sceAudioOutInit 0x%08x", (unsigned)rc );
    port = sceAudioOutOpen( user_id, 0, 0, 256, 48000, 1 );   /* main port, S16 stereo */
    if (port < 0) { lb_set( "audio", "open:0x%08x", (unsigned)port ); return; }
    rc = sceAudioOutOutput( port, silence );
    sceAudioOutClose( port );
    if (rc >= 0) lb_set( "audio", "ok" );
    else lb_set( "audio", "output:0x%08x", (unsigned)rc );
}

/* ------------------------------------------------------------------ i1b: execute after the release */
#ifdef LB_I1B
/* Can code run in pages that were the eboot's code, read-only and read-write segments, and in a
 * page beyond the eboot? Each page three ways: direct memory made RX with sceKernelMprotect, then
 * the same page made RWX, then the page replaced by flexible memory (mmap, anonymous) made RX. Each
 * result is the call's outcome and the protection sceKernelVirtualQuery reports (ORBIS-WIN F3:
 * orbis-win saw Mprotect return 0 while the page stayed read-only). */
typedef struct { void *start, *end; off_t offset; int32_t prot, mtype; uint8_t bits; char name[32]; } lb_vq;

static uint8_t *x_code;
static volatile uint32_t x_got;

static void x_call(void) { x_got = ((uint32_t (*)(void))x_code)(); }

static int x_prot(const void *at)
{
    lb_vq info;
    memset(&info, 0, sizeof(info));
    if (k_vquery(at, 0, &info, sizeof(info))) return -1;
    return info.prot;
}

/* "ok/P", "fault/P", "wrong/P" or "rc:0x..": the call, then the effective protection. */
static void x_try(uint8_t *page, int prot, char *out, size_t size)
{
    static const uint32_t marker = 0x1b1b0000u;
    uint32_t want = marker | (uint32_t)((uintptr_t)page >> 14);
    uint64_t rip = 0, addr = 0;
    int rc, sig;

    x_code = page + 0x100;
    rc = k_mprotect(page, K_GRANULE, K_PROT_RW);
    x_code[0] = 0xB8;
    memcpy(x_code + 1, &want, 4);
    x_code[5] = 0xC3;
    if (!rc) rc = k_mprotect(page, K_GRANULE, prot);
    if (rc) { snprintf(out, size, "rc:0x%08x/%d", (unsigned)rc, x_prot(page)); return; }
    x_got = 0;
    sig = lb_guarded(x_call, &rip, &addr);
    if (sig) snprintf(out, size, "fault/%d", x_prot(page));
    else snprintf(out, size, "%s/%d", x_got == want ? "ok" : "wrong", x_prot(page));
}

static void x_page(const char *key, uintptr_t at)
{
    uint8_t *page = (uint8_t *)(at & ~(uintptr_t)(K_GRANULE - 1));
    char a[32], b[32], c[32];
    void *flex;
    int rc;

    x_try(page, K_PROT_RX, a, sizeof(a));
    x_try(page, K_PROT_RWX, b, sizeof(b));
    /* Flexible memory in its place (the direct memory's slice is unmapped first). */
    rc = k_munmap(page, K_GRANULE);
    flex = rc ? MAP_FAILED : mmap(page, K_GRANULE, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANON, -1, 0);
    if (flex != (void *)page) snprintf(c, sizeof(c), "map:%d", rc ? rc : errno);
    else x_try(page, K_PROT_RX, c, sizeof(c));
    lb_say("  %s page %p: dmem RX %s, dmem RWX %s, flexible RX %s", key, (void *)page, a, b, c);
    lb_set(key, "%s,%s,%s", a, b, c);
}

static void st_i1b(void)
{
    const PwPrxSegment *code = NULL, *ro = NULL, *rw = NULL;
    void *at = (void *)LOW_BASE;
    off_t phys = 0;
    int rc;

    for (uint32_t i = 0; i < released.segment_count; i++) {
        const PwPrxSegment *s = &released.segments[i];
        if ((s->protection & 4) && !code) code = s;
        else if ((s->protection & 2) && !rw) rw = s;
        else if (!(s->protection & 6) && !ro) ro = s;
    }
    /* The PE range as Wine takes it: reserved, then direct memory, read-write. */
    rc = k_reserve(&at, LOW_BYTES, K_MAP_FIXED | K_MAP_NO_OVERWRITE, K_GRANULE);
    if (!rc) rc = k_alloc_direct(0, (off_t)k_direct_size(), LOW_BYTES, K_GRANULE, K_WB_ONION, &phys);
    if (!rc) { at = (void *)LOW_BASE; rc = k_map_direct(&at, LOW_BYTES, K_PROT_RW, K_MAP_FIXED, phys, K_GRANULE); }
    if (rc) { lb_set("x_map", "err:0x%08x", (unsigned)rc); return; }
    lb_set("x_map", "ok");
    /* A page inside each former segment (past its first, which may hold another's tail). */
    if (code) x_page("x_code", (uintptr_t)code->address + K_GRANULE);
    if (ro) x_page("x_ro", (uintptr_t)ro->address + (ro->size > 2 * K_GRANULE ? K_GRANULE : 0));
    if (rw) x_page("x_rw", (uintptr_t)rw->address + K_GRANULE);
    x_page("x_out", LOW_BASE + 0x300000);   /* beyond the eboot, inside Wine's range */
}
#endif

/* ------------------------------------------------------------------ i1c: Wine's image sequence */
#ifdef LB_I1C
/* ps4-wine LOG L20: Wine mapped fixed32.exe's view with direct memory RW at 0x400000+0x420000,
 * then RWX 0x400000+0x4000, RX 0x400000+0x8000, RWX 0x408000+0x4000 (the page .text shares with
 * .data), R 0x40c000+0xc000, RWX then RW 0x418000; all returned 0, yet the shared page ended
 * reported prot 1 and 32-bit code there faulted on execute. Replayed here in region A, and in
 * region B without the neighbouring R protect; the shared page's reported protection after each
 * step; then a 64-bit call into the RX page and the shared page, and a 32-bit call (far jump to
 * selector 0x33, back to 0x43) in the shared page. */
extern uint32_t lb_cs32_enter( const void *farptr );
extern char lb_cs32_resume[];
uint64_t lb_cs32_saved_rsp;
__asm__(
    ".text\n"
    ".globl lb_cs32_enter\n"
    "lb_cs32_enter:\n"
    "    pushq %rbp\n"
    "    movq %rsp, %rbp\n"
    "    pushq %rbx\n"
    "    pushq %r12\n"
    "    pushq %r13\n"
    "    pushq %r14\n"
    "    pushq %r15\n"
    "    movq %rsp, lb_cs32_saved_rsp(%rip)\n"
    "    movl $0x1111, %eax\n"
    "    ljmpl *(%rdi)\n"
    ".globl lb_cs32_resume\n"
    "lb_cs32_resume:\n"
    "    movq lb_cs32_saved_rsp(%rip), %rsp\n"
    "    popq %r15\n"
    "    popq %r14\n"
    "    popq %r13\n"
    "    popq %r12\n"
    "    popq %rbx\n"
    "    popq %rbp\n"
    "    ret\n" );

typedef struct { void *start, *end; off_t offset; int32_t prot, mtype; uint8_t bits; char name[32]; } lb_vq;
static int c_prot(uintptr_t at)
{
    lb_vq info;
    memset(&info, 0, sizeof(info));
    if (k_vquery((const void *)at, 0, &info, sizeof(info))) return -1;
    return info.prot;
}

static uint8_t *c_code;
static volatile uint32_t c_got;
static void c_call64(void) { c_got = ((uint32_t (*)(void))c_code)(); }
static uint8_t *c_far;
static void c_call32(void) { c_got = lb_cs32_enter(c_far); }

/* 64-bit "mov eax, imm; ret" at at. */
static void put64(uint8_t *at, uint32_t value)
{
    at[0] = 0xB8; memcpy(at + 1, &value, 4); at[5] = 0xC3;
}

static const char *c_run(void (*fn)(void), uint32_t want, char *out, size_t size)
{
    uint64_t rip = 0, addr = 0;
    int sig;
    c_got = 0;
    sig = lb_guarded(fn, &rip, &addr);
    if (sig) snprintf(out, size, "fault:%d@0x%lx", sig, (unsigned long)addr);
    else if (c_got == want) snprintf(out, size, "ok");
    else snprintf(out, size, "wrong:0x%x", c_got);
    return out;
}

static void c_region(const char *key, uintptr_t base, int neighbour)
{
    uintptr_t shared = base + 0x8000;
    void *at = (void *)base;
    off_t phys = 0;
    char trail[160], r_rx[48], r_rwx[48], r_32[48];
    size_t n = 0;
    uint32_t low = (uint32_t)shared, back = 0;
    int rc;

    rc = k_reserve(&at, 0x420000, K_MAP_FIXED | K_MAP_NO_OVERWRITE, K_GRANULE);
    if (!rc) rc = k_alloc_direct(0, (off_t)k_direct_size(), 0x420000, K_GRANULE, K_WB_ONION, &phys);
    if (!rc) { at = (void *)base; rc = k_map_direct(&at, 0x420000, K_PROT_RW, K_MAP_FIXED, phys, K_GRANULE); }
    if (rc) { lb_set(key, "map:0x%08x", (unsigned)rc); return; }
    /* The code, while the view is RW (Wine's pread): 64-bit in the RX page and the shared page; in
     * the shared page also 32-bit code that far-jumps back to a 64-bit trampoline there. */
    put64((uint8_t *)base + 0x4100, 0x1c100001u);
    put64((uint8_t *)shared + 0x100, 0x1c100002u);
    {
        uint8_t *c = (uint8_t *)shared + 0x200;
        uint64_t resume = (uint64_t)(uintptr_t)lb_cs32_resume;
        /* +0x200 32-bit: xor eax,eax; dec eax (eax=-1); nop; ljmp 0x43:+0x300 */
        c[0] = 0x31; c[1] = 0xC0; c[2] = 0x48; c[3] = 0x90; c[4] = 0xEA;
        back = low + 0x300; memcpy(c + 5, &back, 4); c[9] = 0x43; c[10] = 0x00;
        /* +0x300 64-bit: jmp *0(%rip) -> lb_cs32_resume */
        c[0x100] = 0xFF; c[0x101] = 0x25; memset(c + 0x102, 0, 4); memcpy(c + 0x106, &resume, 8);
        /* the far pointer 0x33:+0x200, in the RW part of the view */
        c_far = (uint8_t *)base + 0x418000 - 0x18000 + 0x40;
        { uint32_t entry = low + 0x200; memcpy(c_far, &entry, 4); c_far[4] = 0x33; c_far[5] = 0; }
    }
    n += (size_t)snprintf(trail + n, sizeof(trail) - n, "%d", c_prot(shared));
    k_mprotect((void *)base, 0x4000, K_PROT_RWX);
    k_mprotect((void *)base, 0x8000, K_PROT_RX);
    n += (size_t)snprintf(trail + n, sizeof(trail) - n, "/%d", c_prot(shared));
    rc = k_mprotect((void *)shared, 0x4000, K_PROT_RWX);
    n += (size_t)snprintf(trail + n, sizeof(trail) - n, "/rwx%d:%d", rc, c_prot(shared));
    if (neighbour) {
        k_mprotect((void *)(base + 0xc000), 0xc000, 0x1);
        n += (size_t)snprintf(trail + n, sizeof(trail) - n, "/r:%d", c_prot(shared));
    }
    k_mprotect((void *)(base + 0x18000), 0x4000, K_PROT_RWX);
    k_mprotect((void *)(base + 0x18000), 0x400000, K_PROT_RW);
    n += (size_t)snprintf(trail + n, sizeof(trail) - n, "/%d", c_prot(shared));
    k_usleep(200 * 1000);   /* the loader's time between mapping and first call */
    snprintf(trail + n, sizeof(trail) - n, "/%d", c_prot(shared));
    c_code = (uint8_t *)base + 0x4100;
    c_run(c_call64, 0x1c100001u, r_rx, sizeof(r_rx));
    c_code = (uint8_t *)shared + 0x100;
    c_run(c_call64, 0x1c100002u, r_rwx, sizeof(r_rwx));
    c_run(c_call32, 0xffffffffu, r_32, sizeof(r_32));
    lb_say("  %s at %p: shared page prot trail %s; rx64 %s, shared64 %s, shared32 %s", key, (void *)base, trail, r_rx,
           r_rwx, r_32);
    lb_set(key, "%s,%s,%s,%s", r_rx, r_rwx, r_32, trail);
}

static void st_i1c(void)
{
    c_region("c_a", LOW_BASE, 1);
    c_region("c_b", 0x20000000, 0);
}
#endif

/* ------------------------------------------------------------------ the stage runner */
struct stage { const char *id; const char *field; int timeout_s; lb_stage_fn fn; int skippable; };

#if defined(LB_I1C)
static const struct stage stages[] =
{
    { "direct",     "direct_mib", 10, st_direct,     0 },
    { "vo1",        "vo1",        20, st_vo1,        0 },
    { "release",    "release",    20, st_release,    0 },
    { "i1c",        "c_a",        30, st_i1c,        0 },
};
#elif defined(LB_I1B)
static const struct stage stages[] =
{
    { "direct",     "direct_mib", 10, st_direct,     0 },
    { "vo1",        "vo1",        20, st_vo1,        0 },
    { "release",    "release",    20, st_release,    0 },
    { "i1b",        "x_map",      30, st_i1b,        0 },
};
#else
static const struct stage stages[] =
{
    { "direct",     "direct_mib", 10, st_direct,     0 },
    { "vo1",        "vo1",        20, st_vo1,        0 },
    { "release",    "release",    20, st_release,    0 },
    { "reserve400", "reserve400", 10, st_reserve400, 0 },
    { "exec400",    "exec400",    10, st_exec400,    0 },
    { "vo2",        "vo2",        20, st_vo2,        0 },
    { "sysmod",     "sysmod",     20, st_sysmod,     1 },
    { "pad",        "pad",        20, st_pad,        1 },
    { "prx",        "prx",        20, st_prx,        1 },
    { "threads",    "threads",    20, st_threads,    1 },
    { "unwind",     "unwind",     20, st_unwind,     1 },
    { "sigsegv",    "fault",      20, st_fault,      1 },
    { "audio",      "audio",      20, st_audio,      1 },
};
#endif

static void run_stage( const struct stage *s )
{
    uint64_t rip = 0, addr = 0;
    int sig;

    cur_stage = s->id;
    /* Stages 1-6 run on every launch: the release is per process and VideoOut must open first.
     * A later stage that crashed on an earlier launch is recorded and skipped. */
    if (s->skippable && lb_prog_crashed( s->id ))
    {
        lb_say_k( "stage %s crashed on an earlier launch: recorded as crash, skipped", s->id );
        lb_set( s->field, "crash" );
        lb_faults_unresolved++;
        lb_say( "PW_MS stage=%s %s=crash", s->id, s->field );
        return;
    }
    lb_say( "stage %s", s->id );
    lb_prog_mark( 'B', s->id );
    deadline_us = lb_now_us() + (uint64_t)s->timeout_s * 1000000u;
    sig = lb_guarded( s->fn, &rip, &addr );
    deadline_us = 0;
    if (sig)
    {
        lb_say_k( "!! stage %s faulted: signal %d at rip 0x%lx, address 0x%lx", s->id, sig, (unsigned long)rip,
                  (unsigned long)addr );
        lb_set( s->field, "fault@0x%lx", (unsigned long)rip );
        lb_faults_unresolved++;
    }
    lb_prog_mark( 'E', s->id );
    lb_say( "PW_MS stage=%s %s=%s", s->id, s->field, lb_get( s->field ) ? lb_get( s->field ) : "-" );
}

/* 14-15. alive for ALIVE_S with sceGnmSubmitDone on every tick, then the line; the tick goes on,
 * and a gap between ticks (a suspend) is recorded as a stage record. */
static uint64_t tsc(void)
{
    uint32_t lo, hi;
    __asm__ volatile( "rdtsc" : "=a"(lo), "=d"(hi) );
    return (uint64_t)hi << 32 | lo;
}

static void __attribute__((noreturn)) alive_loop(void)
{
    const uint64_t tsc_hz = k_tsc_freq();
    uint64_t start = lb_now_us(), last_pt = start, last_tsc = tsc(), next_beat = start + 10000000u;
    int first_rc = 0, line_done = 0, suspends = 0;

    cur_stage = "alive";
    lb_prog_mark( 'B', "alive" );
    for (;;)
    {
        uint64_t now_pt, now_tsc, gap_pt, gap_tsc_ms;
        int rc = sceGnmSubmitDone();

        if (rc && !first_rc)
        {
            first_rc = rc;
            lb_set( "submitdone", "0x%08x", (unsigned)rc );
        }
        k_usleep( TICK_US );
        now_pt = lb_now_us();
        now_tsc = tsc();
        gap_pt = now_pt - last_pt;
        gap_tsc_ms = tsc_hz ? (now_tsc - last_tsc) * 1000u / tsc_hz : 0;
        if (gap_pt > 2000000u || gap_tsc_ms > 2000u)
        {
            suspends++;
            lb_say_k( "PW_MS stage=suspend resumed=%d gap_s=%llu gap_pt_ms=%llu gap_tsc_ms=%llu after_line=%d",
                      suspends, (unsigned long long)((gap_pt > gap_tsc_ms * 1000u ? gap_pt / 1000u : gap_tsc_ms) / 1000u),
                      (unsigned long long)(gap_pt / 1000u), (unsigned long long)gap_tsc_ms, line_done );
            lb_screen_show( LB_BLUE );
        }
        last_pt = now_pt;
        last_tsc = now_tsc;
        if (now_pt >= next_beat)
        {
            unsigned alive = (unsigned)((now_pt - start) / 1000000u);
            next_beat += 10000000u;
            lb_say( "PW_MS stage=alive alive_s=%u submitdone=0x%08x", alive, (unsigned)first_rc );
            if (!line_done)
            {
                lb_set( "alive_s", "%u", alive );
                if (alive >= ALIVE_S)
                {
                    char line[1536];
                    if (!first_rc) lb_set( "submitdone", "0" );
                    lb_set( "faults_unresolved", "%d", lb_faults_unresolved );
                    lb_prog_mark( 'E', "alive" );
                    lb_results_line( line, sizeof(line), PROBE_BUILD_ID );
                    lb_emit_line( line );
                    lb_prog_done();
                    line_done = 1;
                    lb_say_k( "i1: line printed; the title stays up (PS -> Home and back is recorded only)" );
                }
            }
        }
    }
}

__attribute__((visibility("default"), noreturn)) void lowbase_main( int argc, char **argv )
{
    pthread_t wd;
    int launches;

    probe_netlog_init();
    lb_log_open();
    launches = lb_prog_load();
    lb_say_k( "PS4WINE lowbase start build=%s launch=%d argc=%d argv0=%s", PROBE_BUILD_ID, launches, argc,
              argc > 0 && argv && argv[0] ? argv[0] : "-" );
    lb_guard_install();
    sceUserServiceInitialize( NULL );
    if (sceUserServiceGetInitialUser( &user_id )) user_id = -1;
    if (pthread_create( &wd, NULL, watchdog, NULL )) lb_say_k( "!! no watchdog thread" );

    for (size_t i = 0; i < sizeof(stages) / sizeof(stages[0]); i++) run_stage( &stages[i] );
#if defined(LB_I1C)
    {
        char line[700];
        snprintf( line, sizeof(line), "PS4WINE i1c imageseq release=%s low_end=%s c_a=%s c_b=%s faults_unresolved=%d "
                  "launches=%s build=%s", lb_get( "release" ) ? lb_get( "release" ) : "-",
                  lb_get( "low_end" ) ? lb_get( "low_end" ) : "-", lb_get( "c_a" ) ? lb_get( "c_a" ) : "-",
                  lb_get( "c_b" ) ? lb_get( "c_b" ) : "-", lb_faults_unresolved,
                  lb_get( "launches" ) ? lb_get( "launches" ) : "-", PROBE_BUILD_ID );
        lb_emit_line( line );
        lb_prog_done();
        for (;;) { sceGnmSubmitDone(); k_usleep( 100000 ); }
    }
#elif defined(LB_I1B)
    {
        char line[600];
        snprintf( line, sizeof(line), "PS4WINE i1b execpages release=%s segs=%s low_end=%s x_map=%s x_code=%s x_ro=%s "
                  "x_rw=%s x_out=%s faults_unresolved=%d launches=%s build=%s", lb_get( "release" ) ? lb_get( "release" ) : "-",
                  lb_get( "segs" ) ? lb_get( "segs" ) : "-", lb_get( "low_end" ) ? lb_get( "low_end" ) : "-",
                  lb_get( "x_map" ) ? lb_get( "x_map" ) : "-", lb_get( "x_code" ) ? lb_get( "x_code" ) : "-",
                  lb_get( "x_ro" ) ? lb_get( "x_ro" ) : "-", lb_get( "x_rw" ) ? lb_get( "x_rw" ) : "-",
                  lb_get( "x_out" ) ? lb_get( "x_out" ) : "-", lb_faults_unresolved,
                  lb_get( "launches" ) ? lb_get( "launches" ) : "-", PROBE_BUILD_ID );
        lb_emit_line( line );
        lb_prog_done();
        for (;;) { sceGnmSubmitDone(); k_usleep( 100000 ); }
    }
#endif
    lb_say_k( "i1: stages done (faults %d); alive for %d s with sceGnmSubmitDone", lb_faults_unresolved, ALIVE_S );
    alive_loop();
}

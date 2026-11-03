/* probe_sce.h: the system calls the probe makes, declared here rather than through the SDK's
 * <orbis/...> headers. Several SDK prototypes are wrong (AvailableFlexibleMemorySize and
 * AvailableDirectMemorySize return their results through pointers), and libc's own names
 * (sigaction, sysarch) are bound with asm labels so that FreeBSD's layouts can be used where the
 * SDK's musl headers carry Linux's.
 *
 * The libkernel list follows: alechurri/nx-on-orbis probe/probe.c @ 11b2c65 (GPL-3.0-or-later),
 * lines 49-68.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PROBE_SCE_H
#define PROBE_SCE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

/* ---- libkernel */
extern int32_t  k_alloc_direct( off_t start, off_t end, size_t len, size_t align, int32_t type,
                                off_t *phys ) __asm__("sceKernelAllocateDirectMemory");
extern int32_t  k_map_direct( void **addr, size_t len, int32_t prot, int32_t flags, off_t phys,
                              size_t align ) __asm__("sceKernelMapDirectMemory");
extern int32_t  k_release_direct( off_t phys, size_t len ) __asm__("sceKernelReleaseDirectMemory");
extern int32_t  k_munmap( void *addr, size_t len ) __asm__("sceKernelMunmap");
extern int32_t  k_mprotect( const void *addr, size_t len, int prot ) __asm__("sceKernelMprotect");
extern size_t   k_direct_size(void) __asm__("sceKernelGetDirectMemorySize");
extern int32_t  k_direct_avail( off_t start, off_t end, size_t align, off_t *phys,
                                size_t *size ) __asm__("sceKernelAvailableDirectMemorySize");
extern int32_t  k_flex_avail( size_t *size ) __asm__("sceKernelAvailableFlexibleMemorySize");
extern int32_t  k_reserve( void **addr, size_t len, int32_t flags, size_t align )
                    __asm__("sceKernelReserveVirtualRange");
extern int32_t  k_vquery( const void *addr, int flags, void *info, size_t infosize )
                    __asm__("sceKernelVirtualQuery");
extern uint64_t k_process_time(void) __asm__("sceKernelGetProcessTime");
extern uint64_t k_tsc_freq(void) __asm__("sceKernelGetTscFrequency");
extern int32_t  k_usleep( uint32_t us ) __asm__("sceKernelUsleep");
extern int32_t  k_debug_out( int ch, const char *text ) __asm__("sceKernelDebugOutText");
extern int      k_install_exc( int sig, void (*h)( int, void * ) ) __asm__("sceKernelInstallExceptionHandler");
extern int      k_remove_exc( int sig ) __asm__("sceKernelRemoveExceptionHandler");
extern int32_t  k_load_start_module( const char *path, size_t argc, const void *argv, uint32_t flags,
                                     void *opt, int *result ) __asm__("sceKernelLoadStartModule");
extern int32_t  k_dlsym( int32_t handle, const char *sym, void **addr ) __asm__("sceKernelDlsym");
extern int32_t  k_cpumode(void) __asm__("sceKernelGetCpumode");
extern int      k_is_neo(void) __asm__("sceKernelIsNeoMode");
extern int      k_set_affinity( void *thread, uint64_t mask ) __asm__("scePthreadSetaffinity");
extern void    *k_pthread_self(void) __asm__("scePthreadSelf");

/* FreeBSD's own sigaction / sysarch / cpuset_getaffinity, exported by libkernel. */
struct bsd_sigaction
{
    void   (*handler)( int, void *, void * );
    int      flags;
    uint32_t mask[4];
};
#define BSD_SA_SIGINFO 0x0040
#define BSD_SA_NODEFER 0x0010
extern int k_sigaction( int sig, const struct bsd_sigaction *act, struct bsd_sigaction *old )
               __asm__("sigaction");
extern int k_sysarch( int op, void *parms ) __asm__("sysarch");
extern int k_cpuset_getaffinity( int level, int which, int64_t id, size_t size, void *mask )
               __asm__("cpuset_getaffinity");
extern int k_getppid(void) __asm__("getppid");

/* FreeBSD signal numbers: what the kernel and the exception API take (the SDK's are Linux's). */
#define BSD_SIGILL  4
#define BSD_SIGFPE  8
#define BSD_SIGBUS  10
#define BSD_SIGSEGV 11

#define AMD64_GET_FSBASE 128
#define AMD64_SET_FSBASE 129
#define AMD64_GET_GSBASE 130
#define AMD64_SET_GSBASE 131

/* ---- memory constants */
#define K_PROT_RW        0x03
#define K_PROT_RX        0x05
#define K_PROT_RWX       0x07
#define K_PROT_GPU_RW    0x33   /* CPU RW + GPU RW, for scan-out buffers */
#define K_MAP_FIXED      0x0010
#define K_WB_ONION       0
#define K_WC_GARLIC      3
#define K_GRANULE        0x4000ull

/* ---- libSceVideoOut */
extern int32_t sceVideoOutOpen( int32_t user, int32_t bus, int32_t index, const void *param );
extern int32_t sceVideoOutClose( int32_t handle );
extern void    sceVideoOutSetBufferAttribute( void *attr, uint32_t format, uint32_t tiling,
                                              uint32_t aspect, uint32_t width, uint32_t height,
                                              uint32_t pitch );
extern int32_t sceVideoOutRegisterBuffers( int32_t handle, int32_t start, void *const *addrs,
                                           int32_t count, const void *attr );
extern int32_t sceVideoOutSubmitFlip( int32_t handle, int32_t index, uint32_t mode, int64_t arg );
extern int32_t sceVideoOutSetFlipRate( int32_t handle, int32_t rate );
extern int32_t sceVideoOutIsFlipPending( int32_t handle );

/* ---- libSceAudioOut / libSceUserService / libSceSystemService */
extern int32_t sceAudioOutInit(void);
extern int32_t sceAudioOutOpen( int32_t user, int32_t type, int32_t index, uint32_t len,
                                uint32_t rate, uint32_t param );
extern int32_t sceAudioOutClose( int32_t handle );
extern int32_t sceUserServiceInitialize( void *params );
extern int32_t sceUserServiceGetInitialUser( int32_t *user );
extern int32_t sceSystemServiceLoadExec( const char *path, const char *args[] );
extern int32_t sceSystemServiceHideSplashScreen(void);

/* ---- milestone i1 (probes/lowbase): module info, sysmodule, pad, AudioOut output, GnmDriver, Rtc */
extern int32_t k_module_info( int32_t handle, void *info ) __asm__("sceKernelGetModuleInfo");
extern int32_t sceSysmoduleLoadModule( uint16_t id );
extern int32_t sceSysmoduleGetModuleHandleInternal( uint32_t id, int32_t *handle );
extern int32_t scePadInit(void);
extern int32_t scePadOpen( int32_t user, int32_t type, int32_t index, const void *param );
extern int32_t scePadReadState( int32_t handle, void *state );
extern int32_t sceAudioOutOutput( int32_t handle, const void *samples );
extern int32_t sceGnmSubmitDone(void);
extern int32_t sceRtcGetCurrentTick( uint64_t *tick );

/* ---- libSceNet */
extern int32_t  sceNetInit(void);
extern int32_t  sceNetSocket( const char *name, int32_t family, int32_t type, int32_t proto );
extern int32_t  sceNetSocketClose( int32_t sock );
extern int32_t  sceNetSendto( int32_t sock, const void *buf, size_t len, int32_t flags,
                              const void *addr, uint32_t addrlen );
extern int32_t  sceNetInetPton( int32_t family, const char *src, void *dst );
extern uint16_t sceNetHtons( uint16_t v );

/* ---- probe_netlog.c */
int  probe_netlog_init(void);
void probe_netlog_send( const char *line, size_t len );

#endif /* PROBE_SCE_H */

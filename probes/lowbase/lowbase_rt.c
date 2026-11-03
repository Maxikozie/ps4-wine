/* lowbase_rt.c: the i1 probe's runtime inside lowbase.prx: logging, results and progress, the
 * stage guard and the screen. Everything here lives in the PRX, so it survives the release of the
 * eboot's segments.
 *
 * Logging, results, progress and the screen are copied from probes/probe.c (milestone a), which
 * stays untouched; that code follows alechurri/nx-on-orbis probe/probe.c @ 11b2c65
 * (GPL-3.0-or-later), lines 113-240 and 470-623, and frontend/menu/rom_menu.cpp @ 11b2c65
 * (GPL-3.0-or-later), lines 150-203. The guard here resumes a whole stage (a longjmp from a frame
 * the handler builds) instead of probe.c's single guarded instruction.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "lowbase.h"
#include "probe_sce.h"
#include "probe_util.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MiB (1024ull * 1024ull)

/* ------------------------------------------------------------------ logging */
static FILE *log_file;
static uint64_t t0_us;

uint64_t lb_now_us(void) { return k_process_time(); }

static void say_to( int to_klog, const char *fmt, va_list ap )
{
    char buf[1024];
    int n = snprintf( buf, sizeof(buf), "[%8.3f] ", (double)(lb_now_us() - t0_us) / 1e6 );
    n += vsnprintf( buf + n, sizeof(buf) - n - 2, fmt, ap );
    if (n > (int)sizeof(buf) - 2) n = sizeof(buf) - 2;
    buf[n++] = '\n';
    buf[n] = 0;
    probe_netlog_send( buf, n );
    if (to_klog) k_debug_out( 0, buf );
    if (log_file)
    {
        fwrite( buf, 1, n, log_file );
        fflush( log_file );
        fsync( fileno( log_file ) );
    }
}

void lb_say( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 0, fmt, ap );
    va_end( ap );
}

void lb_say_k( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 1, fmt, ap );
    va_end( ap );
}

/* A result line exactly as check.sh greps it: no timestamp prefix. */
void lb_emit_line( const char *line )
{
    char buf[1536];
    int n = snprintf( buf, sizeof(buf) - 1, "%s\n", line );
    if (n > (int)sizeof(buf) - 1) n = sizeof(buf) - 1;
    probe_netlog_send( buf, n );
    k_debug_out( 0, buf );
    if (log_file) { fwrite( buf, 1, n, log_file ); fflush( log_file ); fsync( fileno( log_file ) ); }
}

void lb_log_open(void)
{
    t0_us = lb_now_us();
    mkdir( "/data/ps4-wine", 0777 );
    mkdir( LB_DIR, 0777 );
    log_file = fopen( LB_LOG, "a" );
}

/* ------------------------------------------------------------------ results and progress */
static struct pr_results results;
static char prog[16384];
static FILE *prog_f;

static void results_save(void)
{
    char buf[PR_MAX_FIELDS * (PR_KEY_LEN + PR_VAL_LEN + 2)];
    FILE *f;
    int n = pr_serialize( &results, buf, sizeof(buf) );

    if (n < 0 || !(f = fopen( LB_RESULTS, "w" ))) return;
    fwrite( buf, 1, n, f );
    fflush( f );
    fsync( fileno( f ) );
    fclose( f );
}

void lb_set( const char *key, const char *fmt, ... )
{
    char val[PR_VAL_LEN];
    va_list ap;

    va_start( ap, fmt );
    vsnprintf( val, sizeof(val), fmt, ap );
    va_end( ap );
    if (pr_set( &results, key, val )) lb_say( "!! cannot record %s=%s", key, val );
    lb_say( "PROBE %s=%s", key, val );
    results_save();
}

void lb_set_rc( const char *key, int rc )
{
    if (rc) lb_set( key, "err:0x%08x", (unsigned)rc );
    else lb_set( key, "ok" );
}

const char *lb_get( const char *key ) { return pr_get( &results, key ); }

void lb_results_line( char *buf, size_t size, const char *build )
{
    if (pr_format_i1_line( &results, build, buf, size ) < 0) snprintf( buf, size, "PS4WINE i1 lowbase line-overflow" );
}

int lb_prog_load(void)
{
    FILE *f = fopen( LB_PROGRESS, "r" );
    size_t n = 0;
    const char *prev;
    int launches = 1;

    prog[0] = 0;
    if (f)
    {
        n = fread( prog, 1, sizeof(prog) - 1, f );
        prog[n] = 0;
        fclose( f );
    }
    pr_init( &results );
    if (pr_prog_fresh( prog ))
    {
        prog[0] = 0;
        prog_f = fopen( LB_PROGRESS, "w" );
        unlink( LB_RESULTS );
    }
    else
    {
        prog_f = fopen( LB_PROGRESS, "a" );
        if ((f = fopen( LB_RESULTS, "r" )))
        {
            char *text = calloc( 1, 8192 );
            if (text)
            {
                fread( text, 1, 8191, f );
                lb_say( "resuming: %d recorded fields", pr_parse( &results, text ) );
                free( text );
            }
            fclose( f );
        }
        if ((prev = pr_get( &results, "launches" ))) launches = atoi( prev ) + 1;
    }
    lb_set( "launches", "%d", launches );
    return launches;
}

void lb_prog_mark( char what, const char *id )
{
    char line[64];
    int n = snprintf( line, sizeof(line), "%c:%s\n", what, id );
    if (!prog_f) return;
    fwrite( line, 1, n, prog_f );
    fflush( prog_f );
    fsync( fileno( prog_f ) );
}

int lb_prog_crashed( const char *id ) { return pr_prog_crashed( prog, id ); }

void lb_prog_done(void) { lb_prog_mark( 'D', "all" ); }

/* ------------------------------------------------------------------ the guard */
static int mc_off = 64;                 /* measured by probe a: mcontext at ucontext+64 */
static volatile int guard_on;
static volatile int guard_sig;
static volatile uint64_t guard_rip, guard_addr;
static jmp_buf guard_jump;
volatile int lb_faults_unresolved;

static __attribute__((noreturn, used)) void guard_escape( jmp_buf *jump )
{
    longjmp( *jump, 1 );
}

/* libkernel's exception API: (signal, ucontext). Inside a guarded stage the handler records the
 * fault and returns into guard_escape on a fresh frame below the faulting one; anywhere else the
 * fault is logged on klog and the process dies (the stage stays B without E). */
static void guard_handler( int sig, void *uc )
{
    uint8_t *mc = (uint8_t *)uc + mc_off;
    uint64_t *rip = (uint64_t *)(mc + PR_MC_RIP);
    uint64_t *rsp = (uint64_t *)(mc + PR_MC_RSP);

    if (guard_on)
    {
        guard_on = 0;
        guard_sig = sig;
        guard_rip = *rip;
        guard_addr = *(uint64_t *)(mc + PR_MC_ADDR);
        *(uint64_t *)(mc + PR_MC_RDI) = (uint64_t)(uintptr_t)&guard_jump;
        *rsp = ((*rsp - 512) & ~15ull) - 8;          /* as if called: rsp % 16 == 8 at entry */
        *rip = (uint64_t)(uintptr_t)guard_escape;
        *(uint64_t *)(mc + PR_MC_CS) = 0x43;
        return;
    }
    lb_faults_unresolved++;
    {
        char line[256];
        snprintf( line, sizeof(line), "!! CRASH: signal %d outside a guarded stage, rip=0x%lx, address 0x%lx\n", sig,
                  (unsigned long)*rip, (unsigned long)*(uint64_t *)(mc + PR_MC_ADDR) );
        k_debug_out( 0, line );
        probe_netlog_send( line, strlen( line ) );
    }
    k_remove_exc( BSD_SIGSEGV );
    k_remove_exc( BSD_SIGBUS );
    k_remove_exc( BSD_SIGILL );
    k_remove_exc( BSD_SIGFPE );
}

void lb_guard_install(void)
{
    k_install_exc( BSD_SIGSEGV, guard_handler );
    k_install_exc( BSD_SIGBUS, guard_handler );
    k_install_exc( BSD_SIGILL, guard_handler );
    k_install_exc( BSD_SIGFPE, guard_handler );
}

int lb_guarded( lb_stage_fn fn, uint64_t *fault_rip, uint64_t *fault_addr )
{
    guard_sig = 0;
    if (setjmp( guard_jump ))
    {
        if (fault_rip) *fault_rip = guard_rip;
        if (fault_addr) *fault_addr = guard_addr;
        return guard_sig ? guard_sig : -1;
    }
    guard_on = 1;
    fn();
    guard_on = 0;
    return 0;
}

/* ------------------------------------------------------------------ screen (probe.c:431-478) */
#define SCREEN_W 1920
#define SCREEN_H 1080
#define SCREEN_BYTES ((size_t)SCREEN_W * SCREEN_H * 4)
#define FMT_A8R8G8B8_SRGB 0x80000000u
#define TILING_LINEAR 1
#define FLIP_VSYNC 1

static int vo_handle = -1;
static void *vo_buf[2];
static int vo_back;

/* The buffers are mapped once and reused by a second open. */
int lb_screen_open( int *rc_out )
{
    const size_t total = (SCREEN_BYTES * 2 + 2 * MiB - 1) & ~(size_t)(2 * MiB - 1);
    uint8_t attr[64] __attribute__((aligned(16)));
    off_t phys = 0;
    void *mem = NULL;
    int rc;

    if (vo_handle >= 0) { *rc_out = 0; return 1; }
    if (!vo_buf[0])
    {
        sceSystemServiceHideSplashScreen();
        rc = k_alloc_direct( 0, (off_t)k_direct_size(), total, 2 * MiB, K_WC_GARLIC, &phys );
        if (!rc) rc = k_map_direct( &mem, total, K_PROT_GPU_RW, 0, phys, 2 * MiB );
        if (rc) { lb_say( "  screen: framebuffer memory refused 0x%08x", (unsigned)rc ); *rc_out = rc; return 0; }
        vo_buf[0] = mem;
        vo_buf[1] = (uint8_t *)mem + SCREEN_BYTES;
    }
    vo_handle = sceVideoOutOpen( 255, 0, 0, NULL );
    if (vo_handle < 0)
    {
        lb_say( "  screen: sceVideoOutOpen 0x%08x", (unsigned)vo_handle );
        *rc_out = vo_handle;
        vo_handle = -1;
        return 0;
    }
    memset( attr, 0, sizeof(attr) );
    sceVideoOutSetBufferAttribute( attr, FMT_A8R8G8B8_SRGB, TILING_LINEAR, 0, SCREEN_W, SCREEN_H, SCREEN_W );
    sceVideoOutSetFlipRate( vo_handle, 0 );
    rc = sceVideoOutRegisterBuffers( vo_handle, 0, vo_buf, 2, attr );
    if (rc < 0)
    {
        lb_say( "  screen: sceVideoOutRegisterBuffers 0x%08x", (unsigned)rc );
        sceVideoOutClose( vo_handle );
        vo_handle = -1;
        *rc_out = rc;
        return 0;
    }
    vo_back = 0;
    *rc_out = 0;
    return 1;
}

int lb_screen_show( uint32_t color )
{
    uint32_t *p;
    size_t i;
    uint64_t t;

    if (vo_handle < 0) return -1;
    t = lb_now_us();
    while (sceVideoOutIsFlipPending( vo_handle ) > 0 && lb_now_us() - t < 500000) k_usleep( 500 );
    p = vo_buf[vo_back];
    for (i = 0; i < (size_t)SCREEN_W * SCREEN_H; i++) p[i] = color;
    i = sceVideoOutSubmitFlip( vo_handle, vo_back, FLIP_VSYNC, 0 );
    vo_back ^= 1;
    return (int)i;
}

int lb_screen_close(void)
{
    int rc;
    uint64_t t = lb_now_us();

    if (vo_handle < 0) return 0;
    while (sceVideoOutIsFlipPending( vo_handle ) > 0 && lb_now_us() - t < 500000) k_usleep( 500 );
    rc = sceVideoOutClose( vo_handle );
    vo_handle = -1;
    return rc;
}

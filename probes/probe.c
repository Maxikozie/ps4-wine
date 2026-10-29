/* probe.c: milestone a's console probe (docs/ps4/MILESTONES.md, ARCHITECTURE.md §6).
 *
 * One ELF, eleven stages, each with a timeout. Progress goes to
 * /data/ps4-wine/probe/progress.txt as B:<stage> / E:<stage> lines, so a stage that crashed or
 * hung on one launch is recorded as "crash" and skipped on the next; results persist in
 * results.txt next to it. The run ends with the machine-readable line
 *     PS4WINE a hello ok build=<id> direct_mib=.. flex_mib=.. reserve_gib=.. jit=.. ...
 * on klog and netlog, a green/amber/red screen, and an idle loop (returning from main is
 * CE-34878-0). The last stage restarts the title through sceSystemServiceLoadExec; the restarted
 * process records the outcome and prints the line again.
 *
 * Stage harness, memory, JIT, fault-resume and VideoOut code follow
 * alechurri/nx-on-orbis probe/probe.c @ 11b2c65 (GPL-3.0-or-later), lines 113-240, 296-464,
 * 470-623, 1112-1140, and frontend/menu/rom_menu.cpp @ 11b2c65 (GPL-3.0-or-later), lines 46-57
 * and 150-203. The marked-MXCSR frame check is the idea of prospero-win's patch 0883 (facts only,
 * no code taken).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "probe_sce.h"
#include "probe_util.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef PROBE_BUILD_ID
#define PROBE_BUILD_ID "unknown"
#endif

#define KiB (1024ull)
#define MiB (1024ull * KiB)
#define GiB (1024ull * MiB)

#define PROBE_DIR      "/data/ps4-wine/probe"
#define PROBE_PROGRESS PROBE_DIR "/progress.txt"
#define PROBE_RESULTS  PROBE_DIR "/results.txt"
#define PROBE_LOG      PROBE_DIR "/probe.log"
#define LOADEXEC_ARG   "--ps4wine-loadexec"

/* ------------------------------------------------------------------ logging */
static FILE *log_file;
static uint64_t t0_us;
static volatile const char *cur_stage = "start";

static uint64_t now_us(void) { return k_process_time(); }

static uint64_t rdtsc(void)
{
    uint32_t lo, hi;
    __asm__ volatile( "rdtsc" : "=a"(lo), "=d"(hi) );
    return (uint64_t)hi << 32 | lo;
}

/* netlog + probe.log always; klog too when to_klog (klog costs 8-15 ms a line and blocks
 * while nothing drains it, so only startup, crash and result lines go there). */
static void say_to( int to_klog, const char *fmt, va_list ap )
{
    char buf[1024];
    int n = snprintf( buf, sizeof(buf), "[%8.3f] ", (double)(now_us() - t0_us) / 1e6 );
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

static void say( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 0, fmt, ap );
    va_end( ap );
}

static void say_k( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    say_to( 1, fmt, ap );
    va_end( ap );
}

/* A result line exactly as check.sh greps it: no timestamp prefix. */
static void emit_line( const char *line )
{
    char buf[1024];
    int n = snprintf( buf, sizeof(buf) - 1, "%s\n", line );
    if (n > (int)sizeof(buf) - 1) n = sizeof(buf) - 1;
    probe_netlog_send( buf, n );
    k_debug_out( 0, buf );
    if (log_file) { fwrite( buf, 1, n, log_file ); fflush( log_file ); fsync( fileno( log_file ) ); }
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

    if (n < 0 || !(f = fopen( PROBE_RESULTS, "w" ))) return;
    fwrite( buf, 1, n, f );
    fflush( f );
    fsync( fileno( f ) );
    fclose( f );
}

static void set_field( const char *key, const char *fmt, ... ) __attribute__((format(printf, 2, 3)));
static void set_field( const char *key, const char *fmt, ... )
{
    char val[PR_VAL_LEN];
    va_list ap;

    va_start( ap, fmt );
    vsnprintf( val, sizeof(val), fmt, ap );
    va_end( ap );
    if (pr_set( &results, key, val )) say( "!! cannot record %s=%s", key, val );
    say( "PROBE %s %s=%s", (const char *)cur_stage, key, val );
    results_save();
}

/* "ok" for rc 0, else "err:0x<rc>". */
static void set_rc( const char *key, int rc )
{
    if (rc) set_field( key, "err:0x%08x", rc );
    else set_field( key, "ok" );
}

static void prog_mark( char what, const char *id )
{
    char line[64];
    int n = snprintf( line, sizeof(line), "%c:%s\n", what, id );
    if (!prog_f) return;
    fwrite( line, 1, n, prog_f );
    fflush( prog_f );
    fsync( fileno( prog_f ) );
}

static void prog_load(void)
{
    FILE *f = fopen( PROBE_PROGRESS, "r" );
    size_t n = 0;
    char *text;

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
        prog_f = fopen( PROBE_PROGRESS, "w" );
        unlink( PROBE_RESULTS );
        return;
    }
    prog_f = fopen( PROBE_PROGRESS, "a" );
    if ((f = fopen( PROBE_RESULTS, "r" )))
    {
        text = calloc( 1, 8192 );
        if (text)
        {
            fread( text, 1, 8191, f );
            say( "resuming: %d recorded fields", pr_parse( &results, text ) );
            free( text );
        }
        fclose( f );
    }
}

/* ------------------------------------------------------------------ watchdog */
static volatile uint64_t deadline_us;
static int timeout_s;

static void *watchdog( void *arg )
{
    (void)arg;
    for (;;)
    {
        uint64_t d = deadline_us;
        k_usleep( 500 * 1000 );
        if (d && d == deadline_us && now_us() > d)
        {
            say_k( "!! HANG: stage %s ran past %d s; the next launch records it as crash and skips it",
                   (const char *)cur_stage, timeout_s );
            k_usleep( 300 * 1000 );
            _exit( 3 );
        }
    }
    return NULL;
}

/* ------------------------------------------------------------------ guarded instructions
 * A guarded helper loads %eax with a marker, executes one instruction that may fault, and returns.
 * When it faults, the exception handler moves rip to the helper's resume label and puts 0xFA57 in
 * rax, so the helper returns 0xFA57 instead of the process dying. */
extern uint64_t probe_load( const void *addr );
extern char probe_load_insn[], probe_load_resume[];
extern uint64_t probe_rdfsbase(void);
extern char probe_rdfsbase_resume[];
extern uint32_t probe_cs32_enter( const void *farptr );
extern char probe_cs32_resume[];
uint64_t probe_cs32_saved_rsp;

__asm__(
    ".text\n"
    ".globl probe_load\n"
    "probe_load:\n"
    "    movl $0x1111, %eax\n"
    ".globl probe_load_insn\n"
    "probe_load_insn:\n"
    "    movq (%rdi), %rax\n"
    ".globl probe_load_resume\n"
    "probe_load_resume:\n"
    "    ret\n"

    ".globl probe_rdfsbase\n"
    "probe_rdfsbase:\n"
    "    movl $0x1111, %eax\n"
    "    rdfsbase %rax\n"
    ".globl probe_rdfsbase_resume\n"
    "probe_rdfsbase_resume:\n"
    "    ret\n"

    /* Far jump through the m16:32 pointer at %rdi (selector 0x33, a stub below 4 GiB); the stub
     * jumps back to selector 0x43 and a trampoline returns here. Upper register halves are not
     * preserved across compatibility mode, so the stack pointer is reloaded from memory. */
    ".globl probe_cs32_enter\n"
    "probe_cs32_enter:\n"
    "    pushq %rbp\n"
    "    movq %rsp, %rbp\n"
    "    pushq %rbx\n"
    "    pushq %r12\n"
    "    pushq %r13\n"
    "    pushq %r14\n"
    "    pushq %r15\n"
    "    movq %rsp, probe_cs32_saved_rsp(%rip)\n"
    "    movl $0x1111, %eax\n"
    "    ljmpl *(%rdi)\n"
    ".globl probe_cs32_resume\n"
    "probe_cs32_resume:\n"
    "    movq probe_cs32_saved_rsp(%rip), %rsp\n"
    "    popq %r15\n"
    "    popq %r14\n"
    "    popq %r13\n"
    "    popq %r12\n"
    "    popq %rbx\n"
    "    popq %rbp\n"
    "    ret\n" );

static int mc_off = 64;                 /* nx-on-orbis measured it; the frame stage re-measures */
static volatile int guard_on;
static volatile int guard_hits;
static volatile int guard_sig;
static volatile uint64_t guard_resume;
static volatile uint64_t guard_addr;
static volatile uint64_t guard_cs;

static void crash_handler( int sig, void *uc )
{
    uint8_t *mc = (uint8_t *)uc + mc_off;
    uint64_t *rip = (uint64_t *)(mc + PR_MC_RIP);

    if (guard_on && guard_hits < 4)
    {
        guard_hits++;
        guard_sig = sig;
        guard_addr = *(uint64_t *)(mc + PR_MC_ADDR);
        guard_cs = *(uint64_t *)(mc + PR_MC_CS);
        *rip = guard_resume;
        *(uint64_t *)(mc + PR_MC_RAX) = 0xFA57;
        *(uint64_t *)(mc + PR_MC_CS) = 0x43;   /* a fault in compatibility mode returns to 64-bit */
        *(uint64_t *)(mc + PR_MC_SS) = 0x3b;
        return;
    }
    say_k( "!! CRASH: signal %d in stage %s, rip=0x%lx (eboot+0x%lx), fault address 0x%lx, rsp=0x%lx",
           sig, (const char *)cur_stage, (unsigned long)*rip, (unsigned long)(*rip - 0x400000ull),
           (unsigned long)*(uint64_t *)(mc + PR_MC_ADDR), (unsigned long)*(uint64_t *)(mc + PR_MC_RSP) );
    say_k( "!! the stage stays marked; the next launch records it as crash and skips it" );
    k_remove_exc( BSD_SIGSEGV );
    k_remove_exc( BSD_SIGBUS );
    k_remove_exc( BSD_SIGILL );
    k_remove_exc( BSD_SIGFPE );
}

static void install_crash_handlers(void)
{
    k_install_exc( BSD_SIGSEGV, crash_handler );
    k_install_exc( BSD_SIGBUS, crash_handler );
    k_install_exc( BSD_SIGILL, crash_handler );
    k_install_exc( BSD_SIGFPE, crash_handler );
}

static void guard_begin( const char *resume )
{
    guard_hits = 0;
    guard_sig = 0;
    guard_cs = 0;
    guard_resume = (uint64_t)(uintptr_t)resume;
    guard_on = 1;
}

static void guard_end(void) { guard_on = 0; }

/* ------------------------------------------------------------------ memory helpers */
static const char *mib( uint64_t bytes )
{
    static char ring[8][32];
    static int i;
    char *s = ring[i++ & 7];
    snprintf( s, 32, "%.1f MiB", (double)bytes / MiB );
    return s;
}

typedef struct { off_t phys; void *va; size_t len; } dblock;

/* Map read-write, then promote to RWX: the only order this kernel grants. */
static int jit_map( dblock *j, size_t len, void *fixed_at, int *rc_out )
{
    int rc;

    memset( j, 0, sizeof(*j) );
    rc = k_alloc_direct( 0, (off_t)k_direct_size(), len, K_GRANULE, K_WB_ONION, &j->phys );
    if (rc) { say( "  jit: no direct memory for %s: 0x%08x", mib( len ), rc ); *rc_out = rc; return 0; }
    j->va = fixed_at;
    rc = k_map_direct( &j->va, len, K_PROT_RW, fixed_at ? K_MAP_FIXED : 0, j->phys, K_GRANULE );
    if (rc || (fixed_at && j->va != fixed_at))
    {
        say( "  jit: map %s at %p refused: 0x%08x (got %p)", mib( len ), fixed_at, rc, j->va );
        if (!rc) k_munmap( j->va, len );
        k_release_direct( j->phys, len );
        *rc_out = rc ? rc : -1;
        return 0;
    }
    j->len = len;
    rc = k_mprotect( j->va, len, K_PROT_RWX );
    if (rc)
    {
        say( "  jit: mprotect RWX on %s at %p refused: 0x%08x", mib( len ), j->va, rc );
        k_munmap( j->va, len );
        k_release_direct( j->phys, len );
        j->len = 0;
        *rc_out = rc;
        return 0;
    }
    *rc_out = 0;
    return 1;
}

static void jit_unmap( dblock *j )
{
    if (!j->len) return;
    k_munmap( j->va, j->len );
    k_release_direct( j->phys, j->len );
    j->len = 0;
}

static int run_stub( void *at, uint32_t value )
{
    uint8_t *c = at;
    uint32_t got;

    c[0] = 0xB8;                    /* mov eax, imm32 */
    memcpy( c + 1, &value, 4 );
    c[5] = 0xC3;                    /* ret */
    got = ((uint32_t (*)(void))at)();
    say( "  generated code at %p returned 0x%08x (expected 0x%08x)", at, got, value );
    return got == value;
}

typedef struct
{
    void   *start;
    void   *end;
    off_t   offset;
    int32_t prot;
    int32_t mtype;
    uint8_t bits;
    char    name[32];
} vq_info;

/* Free means: nothing contains `at`, and the next mapping starts at or after at+len. */
static int range_free( uintptr_t at, size_t len )
{
    vq_info info;

    memset( &info, 0, sizeof(info) );
    if (k_vquery( (const void *)at, 0, &info, sizeof(info) ) == 0 &&
        (uintptr_t)info.start <= at && at < (uintptr_t)info.end)
        return 0;
    memset( &info, 0, sizeof(info) );
    if (k_vquery( (const void *)at, 1, &info, sizeof(info) ) != 0) return 1;
    return (uintptr_t)info.start >= at + len;
}

/* ------------------------------------------------------------------ screen */
#define SCREEN_W 1920
#define SCREEN_H 1080
#define SCREEN_BYTES ((size_t)SCREEN_W * SCREEN_H * 4)
#define FMT_A8R8G8B8_SRGB 0x80000000u     /* pixels are 0xAARRGGBB */
#define TILING_LINEAR 1
#define FLIP_VSYNC 1
#define COLOR_AMBER 0xFFFFA000u
#define COLOR_GREEN 0xFF00C040u
#define COLOR_RED   0xFFD01010u

static int vo_handle = -1;
static void *vo_buf[2];
static int vo_back;

static int screen_open( int *rc_out )
{
    const size_t total = (SCREEN_BYTES * 2 + 2 * MiB - 1) & ~(size_t)(2 * MiB - 1);
    uint8_t attr[64] __attribute__((aligned(16)));
    off_t phys = 0;
    void *mem = NULL;
    int rc;

    if (vo_handle >= 0) return 1;
    sceSystemServiceHideSplashScreen();
    rc = k_alloc_direct( 0, (off_t)k_direct_size(), total, 2 * MiB, K_WC_GARLIC, &phys );
    if (!rc) rc = k_map_direct( &mem, total, K_PROT_GPU_RW, 0, phys, 2 * MiB );
    if (rc) { say( "  screen: framebuffer memory refused 0x%08x", rc ); *rc_out = rc; return 0; }
    vo_handle = sceVideoOutOpen( 255, 0, 0, NULL );
    if (vo_handle < 0) { say( "  screen: sceVideoOutOpen 0x%08x", vo_handle ); *rc_out = vo_handle; vo_handle = -1; return 0; }
    vo_buf[0] = mem;
    vo_buf[1] = (uint8_t *)mem + SCREEN_BYTES;
    memset( attr, 0, sizeof(attr) );
    sceVideoOutSetBufferAttribute( attr, FMT_A8R8G8B8_SRGB, TILING_LINEAR, 0, SCREEN_W, SCREEN_H, SCREEN_W );
    sceVideoOutSetFlipRate( vo_handle, 0 );
    rc = sceVideoOutRegisterBuffers( vo_handle, 0, vo_buf, 2, attr );
    if (rc < 0)
    {
        say( "  screen: sceVideoOutRegisterBuffers 0x%08x", rc );
        sceVideoOutClose( vo_handle );
        vo_handle = -1;
        *rc_out = rc;
        return 0;
    }
    *rc_out = 0;
    return 1;
}

static int screen_show( uint32_t color )
{
    uint32_t *p;
    size_t i;
    uint64_t t;

    if (vo_handle < 0) return -1;
    t = now_us();
    while (sceVideoOutIsFlipPending( vo_handle ) > 0 && now_us() - t < 500000) k_usleep( 500 );
    p = vo_buf[vo_back];
    for (i = 0; i < (size_t)SCREEN_W * SCREEN_H; i++) p[i] = color;
    i = sceVideoOutSubmitFlip( vo_handle, vo_back, FLIP_VSYNC, 0 );
    vo_back ^= 1;
    return (int)i;
}

/* ------------------------------------------------------------------ stages */

/* 1. system facts and flexible memory */
static void st_info(void)
{
    size_t flex = 0;
    int rc = k_flex_avail( &flex );

    say( "  direct memory size %s, neo=%d, cpumode=%d, pid ppid %d", mib( k_direct_size() ),
         k_is_neo(), k_cpumode(), k_getppid() );
    say( "  flexible available %s (rc=0x%08x)", mib( flex ), rc );
    say( "  main at %p, a global at %p, a local at %p", (void *)&st_info, (void *)&results, (void *)&rc );
    if (rc) set_field( "flex_mib", "err:0x%08x", rc );
    else set_field( "flex_mib", "%lu", (unsigned long)(flex / MiB) );
}

/* 2. direct memory ceiling (Q1) */
static dblock blocks[512];

static void st_dmem(void)
{
    static const size_t steps[] = { 256 * MiB, 64 * MiB, 16 * MiB };
    uint64_t total = 0;
    size_t sz = 0;
    off_t phys = 0;
    int n = 0, s, rc;

    rc = k_direct_avail( 0, (off_t)k_direct_size(), 0, &phys, &sz );
    say( "  largest free direct block %s at 0x%lx (rc=0x%08x)", mib( sz ), (unsigned long)phys, rc );
    set_field( "direct_largest_mib", "%lu", (unsigned long)(sz / MiB) );
    for (s = 0; s < 3; s++)
    {
        size_t len = steps[s];
        while (n < (int)(sizeof(blocks) / sizeof(blocks[0])))
        {
            void *va = NULL;
            volatile uint8_t *p;
            size_t o;

            rc = k_alloc_direct( 0, (off_t)k_direct_size(), len, 2 * MiB, K_WB_ONION, &phys );
            if (rc) { say( "  alloc %s refused 0x%08x after %s", mib( len ), rc, mib( total ) ); break; }
            rc = k_map_direct( &va, len, K_PROT_RW, 0, phys, 2 * MiB );
            if (rc)
            {
                say( "  map %s refused 0x%08x after %s", mib( len ), rc, mib( total ) );
                k_release_direct( phys, len );
                break;
            }
            p = va;
            for (o = 0; o < len; o += K_GRANULE) p[o] = (uint8_t)o;
            blocks[n].phys = phys;
            blocks[n].va = va;
            blocks[n].len = len;
            n++;
            total += len;
        }
    }
    say( "  reached %s in %d blocks (mapped RW and touched)", mib( total ), n );
    while (n-- > 0)
    {
        k_munmap( blocks[n].va, blocks[n].len );
        k_release_direct( blocks[n].phys, blocks[n].len );
    }
    set_field( "direct_mib", "%lu", (unsigned long)(total / MiB) );
}

/* 3. reservations, MAP_FIXED, double mapping (Q2) */
static void st_va(void)
{
    static const uint64_t sizes[] = { 1 * GiB, 4 * GiB, 8 * GiB, 16 * GiB, 32 * GiB, 64 * GiB };
    const size_t len = 16 * MiB;
    uint64_t best = 0;
    void *a = NULL, *b = NULL, *res = NULL;
    off_t phys;
    unsigned i;
    int rc, ra, rb, alias = 0, fixed = 0;

    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
    {
        void *at = NULL;
        rc = k_reserve( &at, sizes[i], 0, 2 * MiB );
        say( "  reserve %2lu GiB -> 0x%08x at %p", (unsigned long)(sizes[i] / GiB), rc, at );
        if (!rc) { best = sizes[i]; k_munmap( at, sizes[i] ); }
    }
    set_field( "reserve_gib", "%lu", (unsigned long)(best / GiB) );

    rc = k_alloc_direct( 0, (off_t)k_direct_size(), len, 2 * MiB, K_WB_ONION, &phys );
    if (rc) { set_field( "alias", "err:0x%08x", rc ); return; }
    ra = k_map_direct( &a, len, K_PROT_RW, 0, phys, 2 * MiB );
    rb = k_map_direct( &b, len, K_PROT_RW, 0, phys, 2 * MiB );
    if (!ra && !rb)
    {
        ((volatile uint32_t *)a)[0] = 0x12345678;
        ((volatile uint32_t *)b)[1000] = 0x9abcdef0;
        alias = ((volatile uint32_t *)b)[0] == 0x12345678 && ((volatile uint32_t *)a)[1000] == 0x9abcdef0;
    }
    say( "  double map: 0x%08x at %p, 0x%08x at %p -> %s", ra, a, rb, b, alias ? "aliased" : "no alias" );
    if (!rb) k_munmap( b, len );
    if (!ra) k_munmap( a, len );
    set_field( "alias", alias ? "1" : "0" );

    rc = k_reserve( &res, 64 * MiB, 0, 2 * MiB );
    if (!rc)
    {
        void *at = (uint8_t *)res + 16 * MiB, *got = at;
        rc = k_map_direct( &got, len, K_PROT_RW, K_MAP_FIXED, phys, 2 * MiB );
        fixed = !rc && got == at;
        if (fixed) ((volatile uint32_t *)got)[7] = 7;
        say( "  MAP_FIXED inside a reservation: 0x%08x wanted %p got %p", rc, at, got );
        k_munmap( res, 64 * MiB );
    }
    k_release_direct( phys, len );
    set_field( "map_fixed", fixed ? "1" : "0" );
}

/* 4. JIT recipe and RX narrowing (Q3) */
static void st_jit(void)
{
    dblock j;
    int rc, ok, rx;

    if (!jit_map( &j, 16 * MiB, NULL, &rc )) { set_field( "jit", "err:0x%08x", rc ); return; }
    say( "  16 MiB RWX at %p, %ld MiB from the eboot's code", j.va,
         (long)(((intptr_t)j.va - (intptr_t)&st_jit) / (intptr_t)MiB) );
    ok = run_stub( j.va, 0x00C0FFEE ) && run_stub( (uint8_t *)j.va + 15 * MiB, 0x0BADF00D );
    set_field( "jit", ok ? "ok" : "wrong" );
    rc = k_mprotect( j.va, j.len, K_PROT_RX );
    rx = !rc && ((uint32_t (*)(void))((uint8_t *)j.va + 15 * MiB))() == 0x0BADF00D;
    say( "  narrow to RX: 0x%08x, still runs: %d", rc, rx );
    if (!rx) set_field( "rx", "err:0x%08x", rc );
    rc = k_mprotect( j.va, j.len, K_PROT_RWX );
    say( "  widen back to RWX: 0x%08x", rc );
    if (!rc) run_stub( j.va, 2 );   /* writes: faults if the widen was not honoured */
    if (rx) set_field( "rx", rc ? "narrow_only" : "ok" );
    jit_unmap( &j );
}

/* 5. CPUs and clocks (Q9) */
struct spin { int core; int rc; uint64_t iters; };

static void *spin_thread( void *arg )
{
    struct spin *s = arg;
    volatile uint64_t n = 0;
    uint64_t t;

    s->rc = k_set_affinity( k_pthread_self(), 1ull << s->core );
    t = now_us();
    while (now_us() - t < 300000) n++;
    s->iters = n;
    return NULL;
}

static void st_cpu(void)
{
    struct spin sp[8];
    pthread_t th[8];
    uint64_t mask[2] = { 0, 0 }, best = 0, t, c0, n = 200000000ull, x = 0;
    double tsc_mhz, core_mhz;
    int i, rc, cpus = 0;

    rc = k_cpuset_getaffinity( 3 /* CPU_LEVEL_WHICH */, 2 /* CPU_WHICH_PID */, -1, sizeof(mask), mask );
    say( "  cpuset_getaffinity: %d mask 0x%lx, sysconf(NPROCESSORS_ONLN) %ld", rc,
         (unsigned long)mask[0], sysconf( _SC_NPROCESSORS_ONLN ) );
    if (rc) set_field( "cpu_mask", "err:%d", rc );
    else set_field( "cpu_mask", "0x%lx", (unsigned long)mask[0] );

    /* One spinner per core in the process mask only: a thread whose affinity is refused lands on
     * a core another spinner owns and halves both (the 2026-10-30 run counted 4 of 6 that way). */
    for (i = 0; i < 8; i++)
    {
        sp[i].core = i;
        sp[i].rc = -1;
        sp[i].iters = 0;
        th[i] = 0;
        if (!rc && !(mask[0] & (1ull << i))) continue;
        if (pthread_create( &th[i], NULL, spin_thread, &sp[i] )) th[i] = 0;
    }
    for (i = 0; i < 8; i++) if (th[i]) pthread_join( th[i], NULL );
    for (i = 0; i < 8; i++) if (!sp[i].rc && sp[i].iters > best) best = sp[i].iters;
    for (i = 0; i < 8; i++)
    {
        int full = !sp[i].rc && sp[i].iters >= best / 2;
        if (!th[i]) continue;
        say( "  core %d: affinity rc 0x%08x, %lu iterations%s", i, sp[i].rc, (unsigned long)sp[i].iters,
             full ? "" : " (not usable at full speed)" );
        cpus += full;
    }
    set_field( "cpus", "%d", cpus );

    t = now_us();
    c0 = rdtsc();
    while (now_us() - t < 200000) { }
    tsc_mhz = (double)(rdtsc() - c0) / (double)(now_us() - t);
    t = now_us();
    __asm__ volatile( "1: addq $1, %0\n\taddq $1, %0\n\taddq $1, %0\n\taddq $1, %0\n\tsubq $4, %1\n\tjnz 1b"
                      : "+r"(x), "+r"(n) );
    core_mhz = 200000000.0 / (double)(now_us() - t);
    say( "  TSC %.0f MHz measured, %lu Hz reported; core about %.0f MHz", tsc_mhz,
         (unsigned long)k_tsc_freq(), core_mhz );
    set_field( "tsc_mhz", "%.0f", tsc_mhz );
    set_field( "core_mhz", "%.0f", core_mhz );
}

/* 6. VideoOut and an audio port (Q10) */
static void st_video(void)
{
    const size_t big = (3840ull * 2160 * 4 + 2 * MiB - 1) & ~(size_t)(2 * MiB - 1);
    uint8_t attr[64] __attribute__((aligned(16)));
    void *bufs[2], *mem = NULL;
    off_t phys;
    uint64_t t;
    int rc, n = 0, user = -1, h;

    if (!screen_open( &rc )) { set_field( "videoout", "err:0x%08x", rc ); return; }
    set_field( "videoout", "ok" );
    t = now_us();
    while (now_us() - t < 2000000)
    {
        if (screen_show( (n & 32) ? COLOR_AMBER : 0xFF000000u ) < 0) break;
        n++;
    }
    set_field( "flip_hz", "%.1f", n / ((double)(now_us() - t) / 1e6) );
    screen_show( COLOR_AMBER );

    /* Other buffer sizes, registered as extra sets and never flipped. */
    rc = k_alloc_direct( 0, (off_t)k_direct_size(), big, 2 * MiB, K_WC_GARLIC, &phys );
    if (!rc) rc = k_map_direct( &mem, big, K_PROT_GPU_RW, 0, phys, 2 * MiB );
    if (!rc)
    {
        bufs[0] = mem;
        memset( attr, 0, sizeof(attr) );
        sceVideoOutSetBufferAttribute( attr, FMT_A8R8G8B8_SRGB, TILING_LINEAR, 0, 3840, 2160, 3840 );
        rc = sceVideoOutRegisterBuffers( vo_handle, 2, bufs, 1, attr );
        set_rc( "vo_2160p", rc < 0 ? rc : 0 );
        memset( attr, 0, sizeof(attr) );
        sceVideoOutSetBufferAttribute( attr, FMT_A8R8G8B8_SRGB, TILING_LINEAR, 0, 1280, 720, 1280 );
        rc = sceVideoOutRegisterBuffers( vo_handle, 4, bufs, 1, attr );
        set_rc( "vo_720p", rc < 0 ? rc : 0 );
    }

    rc = sceUserServiceInitialize( NULL );
    say( "  sceUserServiceInitialize 0x%08x", rc );
    rc = sceUserServiceGetInitialUser( &user );
    say( "  initial user %d (0x%08x)", user, rc );
    rc = sceAudioOutInit();
    say( "  sceAudioOutInit 0x%08x", rc );
    h = sceAudioOutOpen( user, 0 /* MAIN */, 0, 256, 48000, 1 /* S16 stereo */ );
    say( "  sceAudioOutOpen -> 0x%08x", h );
    set_rc( "audio", h < 0 ? h : sceAudioOutClose( h ) );
}

/* 7. FS/GS base access (Q4) */
static uint64_t gs_target[2] = { 0x5157475342415345ull, 0 };

static void st_sysarch(void)
{
    uint64_t fs = 0, gs = 0, gs2 = 0, fs0, viags = 0, mark, rd;
    int rfs, rgs, rsetgs = -1, rsetfs, rrestore = -1;

    __asm__ volatile( "movq %%fs:0, %0" : "=r"(fs0) );
    rfs = k_sysarch( AMD64_GET_FSBASE, &fs );
    rgs = k_sysarch( AMD64_GET_GSBASE, &gs );
    say( "  get fsbase 0x%x -> 0x%lx (%%fs:0 says 0x%lx); get gsbase 0x%x -> 0x%lx", rfs,
         (unsigned long)fs, (unsigned long)fs0, rgs, (unsigned long)gs );
    if (!rgs)
    {
        mark = (uint64_t)(uintptr_t)gs_target;
        rsetgs = k_sysarch( AMD64_SET_GSBASE, &mark );
        if (!rsetgs)
        {
            k_sysarch( AMD64_GET_GSBASE, &gs2 );
            __asm__ volatile( "movq %%gs:0, %0" : "=r"(viags) );
            rrestore = k_sysarch( AMD64_SET_GSBASE, &gs );
        }
        say( "  set gsbase 0x%x, read back 0x%lx, %%gs:0 = 0x%lx, restore 0x%x", rsetgs,
             (unsigned long)gs2, (unsigned long)viags, rrestore );
    }
    rsetfs = rfs ? -1 : k_sysarch( AMD64_SET_FSBASE, &fs );   /* same value: harmless */
    say( "  set fsbase (same value) 0x%x", rsetfs );
    {
        int fs_ok = !rfs && !rsetfs && fs == fs0;
        int gs_ok = !rsetgs && gs2 == (uint64_t)(uintptr_t)gs_target && viags == gs_target[0] && !rrestore;
        set_field( "sysarch", fs_ok && gs_ok ? "fs+gs" : fs_ok ? "fs" : gs_ok ? "gs" : "none" );
    }
    set_field( "fsbase", "0x%lx", (unsigned long)(rfs ? fs0 : fs) );

    guard_begin( probe_rdfsbase_resume );
    rd = probe_rdfsbase();
    guard_end();
    if (guard_hits) say( "  rdfsbase faulted with signal %d", guard_sig );
    else say( "  rdfsbase -> 0x%lx", (unsigned long)rd );
    set_field( "rdfsbase", guard_hits ? "0" : rd == fs0 ? "1" : "odd" );
}

/* 8. signal frame layout through sigaction and the exception API (Q5) */
#define FRAME_COPY 1536
static uint8_t frame_copy[2][FRAME_COPY];
static volatile int frame_hits[2];
static volatile int frame_which;
static struct pr_frame_marks frame_marks;

static void frame_capture( void *uc )
{
    uint8_t *u = uc, *dst = frame_copy[frame_which];
    struct pr_frame_layout l;
    int i;

    for (i = 0; i < FRAME_COPY; i++) dst[i] = u[i];
    frame_hits[frame_which]++;
    pr_frame_scan( u, FRAME_COPY, &frame_marks, &l );
    i = l.mc >= 0 ? l.mc : 64;
    *(uint64_t *)(u + i + PR_MC_RIP) = (uint64_t)(uintptr_t)probe_load_resume;
    *(uint64_t *)(u + i + PR_MC_RAX) = 0xFA57;
}

static void frame_sa_handler( int sig, void *info, void *uc ) { (void)sig; (void)info; frame_capture( uc ); }
static void frame_exc_handler( int sig, void *uc ) { (void)sig; frame_capture( uc ); }

static uint64_t frame_fault( const void *target )
{
    uint32_t saved, marked;
    uint64_t got;

    __asm__ volatile( "stmxcsr %0" : "=m"(saved) );
    marked = (saved & ~0x6000u) | 0x2000u;     /* round down: a value nothing else holds */
    frame_marks.mxcsr = marked;
    __asm__ volatile( "fnstcw %0" : "=m"(frame_marks.fcw) );
    __asm__ volatile( "ldmxcsr %0" :: "m"(marked) );
    got = probe_load( target );
    __asm__ volatile( "ldmxcsr %0" :: "m"(saved) );
    return got;
}

static void frame_report( int which, const char *name, struct pr_frame_layout *l )
{
    const uint8_t *f = frame_copy[which];
    char hex[100];
    int row, i, n;

    pr_frame_scan( f, FRAME_COPY, &frame_marks, l );
    say( "  %s: hits %d, mc %d, rip %d, cs 0x%x, fxsave %d, fsbase %d", name, frame_hits[which],
         l->mc, l->rip, l->cs, l->fx, l->fs );
    for (row = 0; row < FRAME_COPY && frame_hits[which]; row += 32)
    {
        for (i = 0, n = 0; i < 32; i++) n += snprintf( hex + n, sizeof(hex) - n, "%02x", f[row + i] );
        say( "  %s +%04d %s", name, row, hex );
    }
}

static void st_frame(void)
{
    struct bsd_sigaction act, old;
    struct pr_frame_layout sa, ex;
    const uint8_t *stub;
    void *res = NULL;
    uint64_t q0, q1, got;
    const char *fsb;
    int rc, rsa, rex;

    rc = k_reserve( &res, 16 * MiB, 0, 2 * MiB );
    if (rc) { set_field( "frame_mc", "err:0x%08x", rc ); return; }
    memset( &frame_marks, 0, sizeof(frame_marks) );
    frame_marks.rip = (uint64_t)(uintptr_t)probe_load_insn;
    frame_marks.fault_addr = (uint64_t)(uintptr_t)res + 4 * MiB + 0x120;
    frame_marks.cs64 = 0x43;
    fsb = pr_get( &results, "fsbase" );
    if (fsb) frame_marks.fsbase = strtoull( fsb, NULL, 16 );
    else __asm__ volatile( "movq %%fs:0, %0" : "=r"(frame_marks.fsbase) );

    /* (a) FreeBSD sigaction with SA_SIGINFO, FreeBSD's flag values and struct layout. */
    k_remove_exc( BSD_SIGSEGV );
    memset( &act, 0, sizeof(act) );
    act.handler = frame_sa_handler;
    act.flags = BSD_SA_SIGINFO | BSD_SA_NODEFER;
    frame_which = 0;
    rsa = k_sigaction( BSD_SIGSEGV, &act, &old );
    got = rsa ? 0 : frame_fault( (const void *)(uintptr_t)frame_marks.fault_addr );
    if (!rsa) k_sigaction( BSD_SIGSEGV, &old, NULL );
    say( "  sigaction rc %d, load returned 0x%lx", rsa, (unsigned long)got );

    /* (b) sceKernelInstallExceptionHandler. */
    frame_which = 1;
    rex = k_install_exc( BSD_SIGSEGV, frame_exc_handler );
    got = rex ? 0 : frame_fault( (const void *)(uintptr_t)frame_marks.fault_addr );
    k_remove_exc( BSD_SIGSEGV );
    k_install_exc( BSD_SIGSEGV, crash_handler );
    say( "  exception handler rc 0x%x, load returned 0x%lx", rex, (unsigned long)got );
    k_munmap( res, 16 * MiB );

    frame_report( 0, "sigaction", &sa );
    frame_report( 1, "sceexc", &ex );
    set_field( "exc", sa.mc >= 0 && ex.mc >= 0 ? "both" : sa.mc >= 0 ? "sigaction" : ex.mc >= 0 ? "sceexc" : "none" );
    {
        struct pr_frame_layout *l = sa.mc >= 0 ? &sa : &ex;
        set_field( "frame_mc", "%d", l->mc );
        set_field( "frame_fx", "%d", l->fx );
        set_field( "frame_fs", "%d", l->fs );
        set_field( "frame_cs", "0x%x", l->cs );
        if (l->mc >= 0) mc_off = l->mc;
    }
    set_field( "exc_layout", "mc%d,fx%d,fs%d", ex.mc, ex.fx, ex.fs );

    /* The shape of libkernel's getppid stub, read under the guard (system text may be execute-only). */
    stub = (const uint8_t *)(uintptr_t)&k_getppid;
    guard_begin( probe_load_resume );
    q0 = probe_load( stub );
    q1 = guard_hits ? 0 : probe_load( stub + 8 );
    guard_end();
    if (guard_hits)
    {
        say( "  getppid at %p is not readable (signal %d)", stub, guard_sig );
        set_field( "stub10", "unreadable" );
    }
    else
    {
        say( "  getppid at %p: %016lx %016lx (little-endian qwords)", stub, (unsigned long)q0, (unsigned long)q1 );
        set_field( "stub10", ((q1 >> 16) & 0xffff) == 0x050f ? "1" : "0" );   /* bytes 10-11 = 0f 05 */
    }
}

/* 9. an application PRX: load, module_start, dlsym (Q8) */
static void st_dlsym(void)
{
    int32_t (*started)(void) = NULL;
    uint32_t (*value)(uint32_t) = NULL;
    int res = 0, h, r1, r2, ok;

    h = k_load_start_module( "/app0/assets/probe_mod.prx", 0, NULL, 0, NULL, &res );
    say( "  sceKernelLoadStartModule -> 0x%08x (module_start result %d)", h, res );
    if (h < 0) { set_field( "dlsym", "load:0x%08x", h ); return; }
    r1 = k_dlsym( h, "probe_mod_started", (void **)&started );
    r2 = k_dlsym( h, "probe_mod_value", (void **)&value );
    say( "  dlsym probe_mod_started 0x%08x %p, probe_mod_value 0x%08x %p", r1, started, r2, value );
    if (r1 || r2 || !started || !value) { set_field( "dlsym", "err:0x%08x", r1 ? r1 : r2 ); return; }
    set_field( "modstart", started() == 0x5157 ? "1" : "0" );
    ok = value( 0x12345678 ) == (0x12345678u ^ 0xA5A5A5A5u);
    set_field( "dlsym", ok ? "ok" : "wrong" );
}

/* 10. a guarded far jump to selector 0x33 and back (Q6) */
static void st_cs32(void)
{
    uintptr_t at = 0, cand;
    uint8_t *c;
    dblock j;
    uint32_t got, low;
    uint64_t back = (uint64_t)(uintptr_t)probe_cs32_resume;
    int rc;

    for (cand = 0x10000000; cand < 0xFF000000; cand += 16 * MiB)
        if (range_free( cand, K_GRANULE )) { at = cand; break; }
    if (!at) { set_field( "cs32", "noaddr" ); return; }
    if (!jit_map( &j, K_GRANULE, (void *)at, &rc )) { set_field( "cs32", "map:0x%08x", rc ); return; }
    say( "  RWX page below 4 GiB at %p", j.va );

    c = j.va;
    low = (uint32_t)at;
    /* +0x000, 32-bit code: xor eax,eax; dec eax (0x48 is REX.W in 64-bit mode: eax stays 0); nop;
     * ljmp 0x43:+0x100 */
    c[0] = 0x31; c[1] = 0xC0; c[2] = 0x48; c[3] = 0x90;
    c[4] = 0xEA;
    { uint32_t tgt = low + 0x100; memcpy( c + 5, &tgt, 4 ); }
    c[9] = 0x43; c[10] = 0x00;
    /* +0x100, 64-bit: jmp *0(%rip) -> probe_cs32_resume */
    c[0x100] = 0xFF; c[0x101] = 0x25; memset( c + 0x102, 0, 4 ); memcpy( c + 0x106, &back, 8 );
    /* +0x200, the m16:32 far pointer 0x33:+0 */
    memcpy( c + 0x200, &low, 4 ); c[0x204] = 0x33; c[0x205] = 0x00;

    guard_begin( probe_cs32_resume );
    got = probe_cs32_enter( c + 0x200 );
    guard_end();
    say( "  far jump returned eax=0x%08x, faults %d (signal %d, frame cs 0x%lx)", got, guard_hits,
         guard_sig, (unsigned long)guard_cs );
    if (got == 0xFFFFFFFFu && !guard_hits) set_field( "cs32", "ok" );
    else if (guard_hits) set_field( "cs32", "fault:%d", guard_sig );
    else set_field( "cs32", "odd:0x%08x", got );
    jit_unmap( &j );
}

/* ------------------------------------------------------------------ stage table */
struct stage
{
    const char *id;
    int timeout_s;
    void (*fn)(void);
    const char *fields;     /* recorded as "crash" when the stage crashed or hung */
};

static const struct stage stages[] =
{
    { "info",    15, st_info,    "flex_mib" },
    { "dmem",    90, st_dmem,    "direct_mib" },
    { "va",      30, st_va,      "reserve_gib" },
    { "jit",     20, st_jit,     "jit" },
    { "cpu",     20, st_cpu,     "cpus" },
    { "video",   20, st_video,   "videoout" },
    { "sysarch", 15, st_sysarch, "sysarch" },
    { "frame",   20, st_frame,   "frame_mc frame_fx frame_fs" },
    { "dlsym",   20, st_dlsym,   "dlsym" },
    { "cs32",    15, st_cs32,    "cs32" },
};

static void run_stage( const struct stage *s )
{
    char fields[64], *f, *save;

    if (pr_prog_ended( prog, s->id )) return;
    cur_stage = s->id;
    if (pr_prog_crashed( prog, s->id ))
    {
        say_k( "== %s: crashed or hung on an earlier launch; recorded as crash", s->id );
        snprintf( fields, sizeof(fields), "%s", s->fields );
        for (f = strtok_r( fields, " ", &save ); f; f = strtok_r( NULL, " ", &save )) set_field( f, "crash" );
        prog_mark( 'E', s->id );
        return;
    }
    prog_mark( 'B', s->id );
    say( "== %s (timeout %d s)", s->id, s->timeout_s );
    timeout_s = s->timeout_s;
    deadline_us = now_us() + (uint64_t)s->timeout_s * 1000000ull;
    s->fn();
    deadline_us = 0;
    prog_mark( 'E', s->id );
    cur_stage = "between stages";
}

static void finish( int done )
{
    char line[1024], extra[1024];
    int i, n, crashed = 0, gate;

    for (i = 0; i < results.count; i++)
        if (!strcmp( results.val[i], "crash" )) crashed = 1;
    gate = pr_gate( &results );
    for (i = 0, n = 0; i < results.count; i++)
        n += snprintf( extra + n, sizeof(extra) - n, " %s=%s", results.key[i], results.val[i] );
    say( "PROBE a all%s", extra );
    if (pr_format_line( &results, PROBE_BUILD_ID, line, sizeof(line) ) < 0) strcpy( line, "PS4WINE a hello overflow" );
    emit_line( line );
    if (vo_handle < 0) { int rc; screen_open( &rc ); }
    screen_show( !gate ? COLOR_RED : crashed ? COLOR_AMBER : COLOR_GREEN );
    if (done) prog_mark( 'D', "all" );
}

int main( int argc, char **argv )
{
    const char *le_args[] = { LOADEXEC_ARG, NULL };
    pthread_t wd;
    int relaunched = 0, i, rc;

    t0_us = now_us();
    probe_netlog_init();
    mkdir( "/data/ps4-wine", 0777 );
    mkdir( PROBE_DIR, 0777 );
    log_file = fopen( PROBE_LOG, "a" );
    /* The PS4 passes LoadExec arguments from argv[0] on (no program name; measured 2026-10-30). */
    for (i = 0; i < argc; i++) if (argv[i] && !strcmp( argv[i], LOADEXEC_ARG )) relaunched = 1;
    say_k( "PS4WINE probe start build=%s argc=%d%s netlog=%s", PROBE_BUILD_ID, argc,
           relaunched ? " relaunched" : "", PROBE_NETLOG_HOST );
    for (i = 0; i < argc; i++) say( "  argv[%d] = %s", i, argv[i] ? argv[i] : "(null)" );

    prog_load();
    prog_mark( 'R', relaunched ? "relaunch" : "launch" );
    install_crash_handlers();
    pthread_create( &wd, NULL, watchdog, NULL );

    for (i = 0; i < (int)(sizeof(stages) / sizeof(stages[0])); i++) run_stage( &stages[i] );

    /* 11. sceSystemServiceLoadExec of our own eboot with an argument (Q7), always last. */
    cur_stage = "loadexec";
    if (pr_prog_crashed( prog, "loadexec" ) || relaunched)
    {
        const char *t = pr_get( &results, "loadexec_t" );
        long dt = t ? (long)time( NULL ) - strtol( t, NULL, 10 ) : -1;
        if (relaunched) set_field( "loadexec", "ok" );
        else set_field( "loadexec", dt >= 0 && dt <= 60 ? "noargs" : "lost" );
        say( "  restart %ld s after the call", dt );
        prog_mark( 'E', "loadexec" );
        finish( 1 );
    }
    else if (!pr_prog_ended( prog, "loadexec" ))
    {
        prog_mark( 'B', "loadexec" );
        set_field( "loadexec_t", "%ld", (long)time( NULL ) );
        set_field( "loadexec", "pending" );
        finish( 0 );
        say_k( "== loadexec: restarting /app0/eboot.bin with %s", LOADEXEC_ARG );
        rc = sceSystemServiceLoadExec( "/app0/eboot.bin", le_args );
        set_field( "loadexec", "err:0x%08x", rc );
        prog_mark( 'E', "loadexec" );
        finish( 1 );
    }
    else finish( 1 );

    say( "probe finished; idling (close the app with the PS button)" );
    for (;;) k_usleep( 1000 * 1000 );
}

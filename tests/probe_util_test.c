/* probe_util_test.c: host tests for probes/probe_util.c (run by scripts/ps4/build.sh probe-test).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "probe_util.h"

#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf( "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond ); failures++; } } while (0)

static void wr64( uint8_t *p, uint64_t v ) { memcpy( p, &v, 8 ); }
static void wr32( uint8_t *p, uint32_t v ) { memcpy( p, &v, 4 ); }
static void wr16( uint8_t *p, uint16_t v ) { memcpy( p, &v, 2 ); }

static void test_results(void)
{
    struct pr_results r, back;
    char buf[4096];
    int n;

    pr_init( &r );
    CHECK( pr_set( &r, "direct_mib", "4464" ) == 0 );
    CHECK( pr_set( &r, "jit", "ok" ) == 0 );
    CHECK( pr_set( &r, "jit", "0x8002000d" ) == 0 );
    CHECK( r.count == 2 );
    CHECK( !strcmp( pr_get( &r, "jit" ), "0x8002000d" ) );
    CHECK( pr_get( &r, "nope" ) == NULL );
    CHECK( pr_set( &r, "bad key", "1" ) == -1 );
    CHECK( pr_set( &r, "k", "a=b" ) == -1 );
    CHECK( pr_set( &r, "k", "" ) == -1 );
    CHECK( pr_set( &r, "k", "x\n" ) == -1 );

    n = pr_serialize( &r, buf, sizeof(buf) );
    CHECK( n > 0 && !strcmp( buf, "direct_mib=4464\njit=0x8002000d\n" ) );
    CHECK( pr_serialize( &r, buf, 8 ) == -1 );

    pr_init( &back );
    CHECK( pr_parse( &back, "direct_mib=4464\r\njit=ok\ngarbage\n=x\nlast=1" ) == 3 );
    CHECK( !strcmp( pr_get( &back, "direct_mib" ), "4464" ) );
    CHECK( !strcmp( pr_get( &back, "jit" ), "ok" ) );
    CHECK( !strcmp( pr_get( &back, "last" ), "1" ) );
}

static void test_line(void)
{
    struct pr_results r;
    char buf[1024];

    pr_init( &r );
    pr_set( &r, "jit", "ok" );
    pr_set( &r, "direct_mib", "4464" );
    pr_set( &r, "flex_mib", "448" );
    pr_set( &r, "reserve_gib", "16" );
    pr_set( &r, "extra", "1" );
    CHECK( pr_format_line( &r, "abc1234+dirty", buf, sizeof(buf) ) > 0 );
    CHECK( !strcmp( buf, "PS4WINE a hello ok build=abc1234+dirty direct_mib=4464 flex_mib=448 "
                         "reserve_gib=16 jit=ok sysarch=- frame_mc=- frame_fx=- frame_fs=- cs32=- "
                         "loadexec=- dlsym=- cpus=-" ) );
    CHECK( pr_format_line( &r, "x", buf, 20 ) == -1 );

    CHECK( pr_gate( &r ) == 1 );
    pr_set( &r, "direct_mib", "3999" );
    CHECK( pr_gate( &r ) == 0 );
    pr_set( &r, "direct_mib", "crash" );
    CHECK( pr_gate( &r ) == 0 );
    pr_set( &r, "direct_mib", "4000" );
    pr_set( &r, "jit", "0x8002000d" );
    CHECK( pr_gate( &r ) == 0 );
}

static void test_progress(void)
{
    const char *prog = "B:info\nE:info\nB:dmem\nE:dmem\nB:jit\nB:jitx\nE:jitx\n";

    CHECK( pr_prog_crashed( prog, "jit" ) );
    CHECK( !pr_prog_crashed( prog, "dmem" ) );
    CHECK( !pr_prog_crashed( prog, "ji" ) );
    CHECK( !pr_prog_crashed( prog, "va" ) );
    CHECK( pr_prog_ended( prog, "jitx" ) );
    CHECK( !pr_prog_ended( prog, "jit" ) );
    CHECK( !pr_prog_fresh( prog ) );
    CHECK( pr_prog_fresh( "" ) );
    CHECK( pr_prog_fresh( "B:info\nE:info\nD:all\n" ) );
    CHECK( pr_prog_crashed( "B:last", "last" ) );
}

/* Builds a ucontext image: mcontext at mc_off, FXSAVE at fx_off, FS base at fs_off. */
static void build_frame( uint8_t *uc, size_t len, const struct pr_frame_marks *m,
                         int mc_off, int fx_off, int fs_off )
{
    memset( uc, 0xcc, len );
    wr64( uc + mc_off + PR_MC_ADDR, m->fault_addr );
    wr64( uc + mc_off + PR_MC_RIP, m->rip );
    wr64( uc + mc_off + PR_MC_CS, m->cs64 );
    wr64( uc + mc_off + PR_MC_SS, 0x3b );
    wr16( uc + fx_off, m->fcw );
    wr32( uc + fx_off + 24, m->mxcsr );
    wr64( uc + fs_off, m->fsbase );
}

static void test_frame(void)
{
    static uint8_t uc[1536];
    struct pr_frame_marks m = { 0x401234, 0x200400123, 0x3f80, 0x037f, 0x8a0004000, 0x43 };
    struct pr_frame_layout l;

    /* PS5 as measured by prospero-win (patches 0500/0501/0883): mc +64, FXSAVE +320, FS +1152. */
    build_frame( uc, sizeof(uc), &m, 64, 320, 1152 );
    pr_frame_scan( uc, sizeof(uc), &m, &l );
    CHECK( l.mc == 64 && l.rip == 224 && l.cs == 0x43 && l.fx == 320 && l.fs == 1152 );

    /* Stock FreeBSD 9 amd64 layout shifted to mc +64: mc_fpstate at +224, mc_fsbase at +736. */
    build_frame( uc, sizeof(uc), &m, 64, 64 + 224, 64 + 736 );
    pr_frame_scan( uc, sizeof(uc), &m, &l );
    CHECK( l.mc == 64 && l.fx == 288 && l.fs == 800 );

    /* A decoy RIP value earlier in the frame (a saved register) without the matching fault address. */
    build_frame( uc, sizeof(uc), &m, 64, 320, 1152 );
    wr64( uc + 8, m.rip );
    pr_frame_scan( uc, sizeof(uc), &m, &l );
    CHECK( l.mc == 64 );

    /* A decoy FS base inside the mcontext registers must not win over the one after FXSAVE. */
    wr64( uc + 64 + 8, m.fsbase );
    pr_frame_scan( uc, sizeof(uc), &m, &l );
    CHECK( l.fs == 1152 );

    /* Nothing planted: everything reports -1. */
    memset( uc, 0, sizeof(uc) );
    pr_frame_scan( uc, sizeof(uc), &m, &l );
    CHECK( l.mc == -1 && l.rip == -1 && l.cs == -1 && l.fx == -1 && l.fs == -1 );

    CHECK( pr_find_u64( (const uint8_t *)"\x01\0\0\0\0\0\0\0", 8, 0, 1 ) == 0 );
    CHECK( pr_find_u64( (const uint8_t *)"\x01\0\0\0\0\0\0\0", 8, 1, 1 ) == -1 );
}

/* The i1 line: gated fields first, then the recorded ones, build last; "-" for what was not
 * measured. netlog carries it whole; klog keeps 512 bytes of a line, so the gated part (up to
 * faults_unresolved) must fit there even with every field at a long value. */
static void test_i1_line(void)
{
    struct pr_results r;
    char buf[1536];
    int i, n;

    pr_init( &r );
    pr_set( &r, "direct_mib", "4464" );
    pr_set( &r, "release", "ok" );
    pr_set( &r, "launches", "2" );
    CHECK( pr_format_i1_line( &r, "abc1234", buf, sizeof(buf) ) > 0 );
    CHECK( !strncmp( buf, "PS4WINE i1 lowbase direct_mib=4464 release=ok reserve400=- ", 59 ) );
    CHECK( strstr( buf, " launches=2 build=abc1234" ) && !strcmp( strstr( buf, " build=" ), " build=abc1234" ) );
    CHECK( strstr( buf, " alive_s=- faults_unresolved=- segs=- " ) != NULL );
    CHECK( pr_format_i1_line( &r, "x", buf, 30 ) == -1 );
    for (i = 0; pr_i1_fields[i]; i++) pr_set( &r, pr_i1_fields[i], "err:0x80020016" );
    n = pr_format_i1_line( &r, "0123456+dirty", buf, sizeof(buf) );
    CHECK( n > 0 && strstr( buf, " segs=" ) && strstr( buf, " segs=" ) - buf < 512 - 32 );
}

int main(void)
{
    test_results();
    test_line();
    test_i1_line();
    test_progress();
    test_frame();
    if (failures) { printf( "probe_util_test: %d failure(s)\n", failures ); return 1; }
    printf( "probe_util_test: all passed\n" );
    return 0;
}

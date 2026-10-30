/* triangle_caps_test.c: host tests for probes/triangle_caps.c (run by scripts/ps4/build.sh probe-test).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "triangle_caps.h"

#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf( "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond ); failures++; } } while (0)

static void test_ext(void)
{
    const char *names[] = { "VK_KHR_swapchain", "VK_KHR_maintenance5", "VK_EXT_robustness2" };
    CHECK( tc_has_ext( names, 3, "VK_KHR_maintenance5" ) );
    CHECK( !tc_has_ext( names, 3, "VK_KHR_maintenance" ) );
    CHECK( !tc_has_ext( names, 0, "VK_KHR_swapchain" ) );
}

static void test_api(void)
{
    char buf[16];
    tc_api_string( (1u << 22) | (3u << 12) | 358, buf, sizeof(buf) );   /* 1.3.358, as measured */
    CHECK( !strcmp( buf, "1.3" ) );
    tc_api_string( (1u << 22) | (2u << 12), buf, sizeof(buf) );
    CHECK( !strcmp( buf, "1.2" ) );
}

static void test_line(void)
{
    struct pr_results r;
    char buf[1024], small[40];
    int n;

    pr_init( &r );
    pr_set( &r, "fps", "59.9" );   /* order of setting does not matter */
    pr_set( &r, "frames", "300" );
    pr_set( &r, "api", "1.3" );
    pr_set( &r, "maintenance5", "1" );
    pr_set( &r, "robustness2", "1" );
    pr_set( &r, "gpl", "1" );
    pr_set( &r, "dyn_rendering", "1" );
    pr_set( &r, "xfb", "1" );
    pr_set( &r, "cond_render", "0" );
    n = tc_format_line( &r, "abc1234+dirty", buf, sizeof(buf) );
    CHECK( n == (int)strlen( buf ) );
    CHECK( !strncmp( buf, "PS4WINE b triangle frames=300 api=1.3 maintenance5=1 robustness2=1 gpl=1 "
                          "dyn_rendering=1 xfb=1 build=abc1234+dirty edyn3=- ", 115 ) );
    CHECK( strstr( buf, " cond_render=0 indirect_count=- " ) != NULL );
    CHECK( strstr( buf, " fps=59.9 gpu_hang=- err=-" ) != NULL );
    CHECK( n < 512 );   /* one netlog datagram */
    CHECK( tc_format_line( &r, "abc1234", small, sizeof(small) ) == -1 );
}

static void test_pack(void)
{
    const char *names[] = { "VK_A", "VK_BB", "VK_CCC", "VK_A_VERY_LONG_EXTENSION_NAME", "VK_D" };
    char buf[64];
    unsigned next = 0;
    int n;

    n = tc_pack_names( "ext", names, 5, &next, 16, buf, sizeof(buf) );
    CHECK( !strcmp( buf, "ext VK_A VK_BB" ) && n == 14 && next == 2 );
    n = tc_pack_names( "ext", names, 5, &next, 16, buf, sizeof(buf) );
    CHECK( !strcmp( buf, "ext VK_CCC" ) && next == 3 );
    n = tc_pack_names( "ext", names, 5, &next, 16, buf, sizeof(buf) );   /* too long: truncated alone */
    CHECK( !strcmp( buf, "ext VK_A_VERY_LO" ) && n == 16 && next == 4 );
    n = tc_pack_names( "ext", names, 5, &next, 16, buf, sizeof(buf) );
    CHECK( !strcmp( buf, "ext VK_D" ) && next == 5 );
    CHECK( tc_pack_names( "ext", names, 5, &next, 16, buf, sizeof(buf) ) == 0 );
    next = 0;
    CHECK( tc_pack_names( "ext", names, 5, &next, 64, buf, sizeof(buf) ) == 0 );   /* width >= size */
}

int main(void)
{
    test_ext();
    test_api();
    test_line();
    test_pack();
    if (failures) { printf( "triangle_caps_test: %d failure(s)\n", failures ); return 1; }
    printf( "triangle_caps_test: all passed\n" );
    return 0;
}

/* stub.c: the i1 probe's eboot (docs/ps4/HANDOFF-i.md, "i1, the probe"). It loads
 * /app0/sce_module/lowbase.prx, runs its module_start (the loader runs neither constructors nor
 * module_start), finds lowbase_main through the PRX's PRXDESC1 descriptor, hands it argc/argv and
 * never runs again: lowbase.prx unmaps this eboot's segments. Its frames stay on the main
 * thread's stack below lowbase_main, which is what stage 11's backtrace walks into.
 *
 * From: plastikman/orbis-win src/reloc-wine-app/stub.c @ 2610706 (LGPL-2.1-or-later): load the
 * PRX, read its segments, find the descriptor, call the entry with argc/argv, idle on failure. The
 * module-info parse and the descriptor scan are prospero-win's own (our fork,
 * third_party/prospero-win/wine/ps5/pw_wine_prx.c, LGPL-2.1-or-later), compiled in from there.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "probe_sce.h"
#include "pw_wine_prx.h"

#include <stdio.h>
#include <string.h>

#ifndef LB_STUB_TLS_BYTES
#error "build.sh lowbase sets LB_STUB_TLS_BYTES from lowbase.prx's PT_TLS"
#endif
#ifndef PROBE_BUILD_ID
#define PROBE_BUILD_ID "unknown"
#endif

#define LB_PRX "/app0/sce_module/lowbase.prx"

/* A PRX's thread-locals are relaxed by lld to local-exec offsets into the main executable's
 * block (third_party/prospero-win/wine/orbis/pw_emutls_orbis.c:4-14), so this eboot's PT_TLS is
 * the storage for lowbase.prx's. It must be at least as large and stay .tbss only (filesz 0: no
 * initialisation image in the segments that get released). build.sh checks both. */
__thread uint64_t lb_stub_tls_room[(LB_STUB_TLS_BYTES + 7) / 8];

static void say( const char *text )
{
    k_debug_out( 0, text );
}

static void __attribute__((noreturn)) idle( const char *why )
{
    say( why );
    for (;;) k_usleep( 1000 * 1000 );
}

int main( int argc, char **argv )
{
    uint8_t info[PW_PRX_MODULE_INFO_BYTES];
    uint64_t size_word = sizeof(info);
    PwPrxSegment segments[PW_PRX_MAX_SEGMENTS];
    const PwPrxDescriptor *desc = NULL;
    int (*module_start)( size_t, const void * );
    void (*entry)( int, char ** );
    uint32_t count = 0;
    int result = 0, handle, rc;
    char line[192];

    /* Keep the room linked: link.x drops an unreferenced .tbss. */
    (void)*(volatile uint64_t *)&lb_stub_tls_room[0];
    snprintf( line, sizeof(line), "PS4WINE lowbase stub build=%s argc=%d tls_room=%d\n", PROBE_BUILD_ID, argc,
              (int)sizeof(lb_stub_tls_room) );
    say( line );

    handle = k_load_start_module( LB_PRX, 0, NULL, 0, NULL, &result );
    if (handle < 0)
    {
        snprintf( line, sizeof(line), "PS4WINE lowbase stub load=0x%08x result=0x%x: idle\n", (unsigned)handle, (unsigned)result );
        idle( line );
    }
    memset( info, 0, sizeof(info) );
    memcpy( info, &size_word, sizeof(size_word) );
    rc = k_module_info( handle, info );
    memcpy( info, &size_word, sizeof(size_word) );
    if (rc || pw_prx_parse_module_info( info, NULL, segments, &count ) != PW_PRX_OK ||
        pw_prx_find_descriptor( segments, count, &desc ) != PW_PRX_OK)
    {
        snprintf( line, sizeof(line), "PS4WINE lowbase stub module_info=0x%08x segments=%u descriptor=%s: idle\n",
                  (unsigned)rc, count, desc ? "ok" : "none" );
        idle( line );
    }
    module_start = (int (*)( size_t, const void * ))pw_prx_lookup( desc, "module_start" );
    entry = (void (*)( int, char ** ))pw_prx_lookup( desc, "lowbase_main" );
    if (!module_start || !entry) idle( "PS4WINE lowbase stub: module_start or lowbase_main missing: idle\n" );
    if ((rc = module_start( 0, NULL )))
    {
        snprintf( line, sizeof(line), "PS4WINE lowbase stub module_start=%d: idle\n", rc );
        idle( line );
    }
    say( "PS4WINE lowbase stub: entering lowbase.prx; this eboot is not resumed\n" );
    entry( argc, argv );
    idle( "PS4WINE lowbase stub: lowbase_main returned (it must not): idle\n" );
}

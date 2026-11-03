/* lowbase_mod.c: the PRXs the i1 probe loads after the eboot's release (stage 9).
 *
 * lowbase_mod.prx: module_start and lowbase_mod_value; it NEEDs nothing the stub lacks (gated:
 * prx). Built with -DLB_MOD2 as lowbase_mod2.prx, it also calls sceRtcGetCurrentTick, so it NEEDs
 * libSceRtc, which neither the stub nor lowbase.prx loads (recorded: prx_sce). That answers
 * whether a PRX loaded after the release may NEED a Sony library the eboot does not.
 *
 * module_start, module_stop and the PRXDESC1 table come from the descriptor unit that
 * gen_prx_descriptor.py --orbis writes for each (build.sh lowbase).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stdint.h>

#ifdef LB_MOD2
extern int32_t sceRtcGetCurrentTick( uint64_t *tick );

__attribute__((visibility("default"))) int lowbase_mod2_tick( uint64_t *tick )
{
    return sceRtcGetCurrentTick( tick );
}
#endif

static volatile uint32_t started = 0x5157;

__attribute__((visibility("default"))) uint32_t lowbase_mod_value( uint32_t x )
{
    return (x ^ 0xA5A5A5A5u) + (started == 0x5157 ? 0 : 1);
}

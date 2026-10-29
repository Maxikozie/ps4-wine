/* probe_mod.c: a minimal application PRX for the probe's dlsym stage (ARCHITECTURE §6 Q8).
 * Linked with the SDK's crtlib.o, whose module_start runs .init_array: the constructor below
 * proves module_start ran, probe_mod_value() proves sceKernelDlsym resolved an export.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stdint.h>

static volatile int32_t started;

__attribute__((constructor)) static void probe_mod_ctor(void)
{
    started = 0x5157;
}

__attribute__((visibility("default"))) int32_t probe_mod_started(void)
{
    return started;
}

__attribute__((visibility("default"))) uint32_t probe_mod_value(uint32_t x)
{
    return x ^ 0xA5A5A5A5u;
}

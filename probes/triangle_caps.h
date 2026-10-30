/* triangle_caps.h: the milestone b title's pure helpers (no Vulkan, no libkernel), so they can be
 * unit-tested on the host (tests/triangle_caps_test.c). Values are kept in probe_util's pr_results.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef TRIANGLE_CAPS_H
#define TRIANGLE_CAPS_H

#include <stddef.h>
#include <stdint.h>

#include "probe_util.h"

/* The fields of the PS4WINE b line, in order: the gated ones (docs/ps4/MILESTONES.md), then the
 * recorded ones. "build" is inserted after the gated fields. */
extern const char *const tc_gated_fields[];
extern const char *const tc_recorded_fields[];

/* 1 when name is in names[0..count). */
int tc_has_ext( const char *const *names, unsigned count, const char *name );

/* "major.minor" of a VK_MAKE_API_VERSION value (variant bits ignored). */
void tc_api_string( uint32_t api, char *buf, size_t size );

/* "PS4WINE b triangle frames=.. api=.. ... build=<build> edyn3=.. ..." with "-" for a field not
 * set. Returns the length, or -1 if it did not fit. */
int tc_format_line( const struct pr_results *r, const char *build, char *buf, size_t size );

/* Packs names[*next..count) into buf as "<prefix> name name ...", at most width bytes (excluding
 * the NUL; width < size), advancing *next past the names written. A name longer than the room left
 * after the prefix is written alone, truncated. Returns the length, or 0 when *next == count. */
int tc_pack_names( const char *prefix, const char *const *names, unsigned count, unsigned *next,
                   size_t width, char *buf, size_t size );

#endif /* TRIANGLE_CAPS_H */

/* triangle_caps.c: the milestone b title's pure helpers. Built for the PS4 into the triangle and
 * for the host into tests/triangle_caps_test.c.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "triangle_caps.h"

#include <stdio.h>
#include <string.h>

const char *const tc_gated_fields[] =
{
    "frames", "api", "maintenance5", "robustness2", "gpl", "dyn_rendering", "xfb", NULL
};

const char *const tc_recorded_fields[] =
{
    "edyn3", "desc_idx", "timeline", "bda", "cbc", "dce", "cond_render", "indirect_count",
    "exts", "heap0_mib", "max_alloc_mib", "swapchain", "fmt", "fps", "gpu_hang", "err", "fb", NULL
};

int tc_has_ext( const char *const *names, unsigned count, const char *name )
{
    unsigned i;
    for (i = 0; i < count; i++) if (names[i] && !strcmp( names[i], name )) return 1;
    return 0;
}

void tc_api_string( uint32_t api, char *buf, size_t size )
{
    snprintf( buf, size, "%u.%u", (unsigned)(api >> 22) & 0x7f, (unsigned)(api >> 12) & 0x3ff );
}

static int tc_append_fields( const struct pr_results *r, const char *const *fields, char *buf,
                             size_t size, size_t *n )
{
    int i, w;
    for (i = 0; fields[i]; i++)
    {
        const char *v = pr_get( r, fields[i] );
        w = snprintf( buf + *n, size - *n, " %s=%s", fields[i], v ? v : "-" );
        if (w < 0 || (size_t)w >= size - *n) return -1;
        *n += w;
    }
    return 0;
}

int tc_format_line( const struct pr_results *r, const char *build, char *buf, size_t size )
{
    size_t n;
    int w = snprintf( buf, size, "PS4WINE b triangle" );
    if (w < 0 || (size_t)w >= size) return -1;
    n = w;
    if (tc_append_fields( r, tc_gated_fields, buf, size, &n ) < 0) return -1;
    w = snprintf( buf + n, size - n, " build=%s", build );
    if (w < 0 || (size_t)w >= size - n) return -1;
    n += w;
    if (tc_append_fields( r, tc_recorded_fields, buf, size, &n ) < 0) return -1;
    return (int)n;
}

int tc_pack_names( const char *prefix, const char *const *names, unsigned count, unsigned *next,
                   size_t width, char *buf, size_t size )
{
    size_t n, len;
    int first = 1;

    if (*next >= count || width >= size) return 0;
    n = strlen( prefix );
    if (n >= width) return 0;
    memcpy( buf, prefix, n );
    while (*next < count)
    {
        len = strlen( names[*next] );
        if (n + 1 + len > width)
        {
            if (!first) break;
            len = width - n - 1;   /* one over-long name: write it truncated rather than loop */
        }
        buf[n++] = ' ';
        memcpy( buf + n, names[*next], len );
        n += len;
        ++*next;
        first = 0;
    }
    buf[n] = 0;
    return (int)n;
}

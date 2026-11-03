/* probe_util.c: the probe's pure helpers. Built for the PS4 into the probe and for the host
 * into tests/probe_util_test.c.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "probe_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *const pr_line_fields[] =
{
    "direct_mib", "flex_mib", "reserve_gib", "jit", "sysarch", "frame_mc", "frame_fx",
    "frame_fs", "cs32", "loadexec", "dlsym", "cpus", NULL
};

void pr_init( struct pr_results *r )
{
    memset( r, 0, sizeof(*r) );
}

static int pr_token_ok( const char *s, size_t max )
{
    size_t n = strlen( s );
    if (!n || n >= max) return 0;
    return strcspn( s, " =\t\r\n" ) == n;
}

int pr_set( struct pr_results *r, const char *key, const char *val )
{
    int i;

    if (!pr_token_ok( key, PR_KEY_LEN ) || !pr_token_ok( val, PR_VAL_LEN )) return -1;
    for (i = 0; i < r->count; i++)
        if (!strcmp( r->key[i], key )) break;
    if (i == r->count)
    {
        if (r->count == PR_MAX_FIELDS) return -1;
        r->count++;
        strcpy( r->key[i], key );
    }
    strcpy( r->val[i], val );
    return 0;
}

const char *pr_get( const struct pr_results *r, const char *key )
{
    int i;

    for (i = 0; i < r->count; i++)
        if (!strcmp( r->key[i], key )) return r->val[i];
    return NULL;
}

int pr_parse( struct pr_results *r, const char *text )
{
    char line[PR_KEY_LEN + PR_VAL_LEN + 4];
    const char *p = text, *nl, *eq;
    size_t n;
    int read = 0;

    while (*p)
    {
        nl = strchr( p, '\n' );
        n = nl ? (size_t)(nl - p) : strlen( p );
        if (n < sizeof(line))
        {
            memcpy( line, p, n );
            line[n] = 0;
            if (n && line[n - 1] == '\r') line[n - 1] = 0;
            if ((eq = strchr( line, '=' )) && eq != line)
            {
                line[eq - line] = 0;
                if (!pr_set( r, line, eq + 1 )) read++;
            }
        }
        if (!nl) break;
        p = nl + 1;
    }
    return read;
}

int pr_serialize( const struct pr_results *r, char *buf, size_t size )
{
    size_t len = 0;
    int i, n;

    if (!size) return -1;
    buf[0] = 0;
    for (i = 0; i < r->count; i++)
    {
        n = snprintf( buf + len, size - len, "%s=%s\n", r->key[i], r->val[i] );
        if (n < 0 || (size_t)n >= size - len) return -1;
        len += n;
    }
    return (int)len;
}

int pr_format_line( const struct pr_results *r, const char *build, char *buf, size_t size )
{
    const char *v;
    size_t len;
    int i, n;

    n = snprintf( buf, size, "PS4WINE a hello ok build=%s", build );
    if (n < 0 || (size_t)n >= size) return -1;
    len = n;
    for (i = 0; pr_line_fields[i]; i++)
    {
        v = pr_get( r, pr_line_fields[i] );
        n = snprintf( buf + len, size - len, " %s=%s", pr_line_fields[i], v ? v : "-" );
        if (n < 0 || (size_t)n >= size - len) return -1;
        len += n;
    }
    return (int)len;
}

int pr_gate( const struct pr_results *r )
{
    const char *d = pr_get( r, "direct_mib" ), *j = pr_get( r, "jit" );
    char *end;
    long mib;

    if (!d || !j || strcmp( j, "ok" )) return 0;
    mib = strtol( d, &end, 10 );
    return *end == 0 && end != d && mib >= 4000;
}

const char *const pr_i1_fields[] =
{
    "direct_mib", "release", "reserve400", "exec400", "vo2", "prx", "threads", "tls", "fault", "alive_s",
    "faults_unresolved", "segs", "low_end", "module0_after", "sysmod", "kbd_open", "pad", "unwind",
    "submitdone", "audio", "pre_reserve", "vo1", "vo1_close", "prx_sce", "unwind_frames", "unwind_eboot",
    "launches", NULL
};

int pr_format_i1_line( const struct pr_results *r, const char *build, char *buf, size_t size )
{
    const char *v;
    size_t len;
    int i, n;

    n = snprintf( buf, size, "PS4WINE i1 lowbase" );
    if (n < 0 || (size_t)n >= size) return -1;
    len = n;
    for (i = 0; pr_i1_fields[i]; i++)
    {
        v = pr_get( r, pr_i1_fields[i] );
        n = snprintf( buf + len, size - len, " %s=%s", pr_i1_fields[i], v ? v : "-" );
        if (n < 0 || (size_t)n >= size - len) return -1;
        len += n;
    }
    n = snprintf( buf + len, size - len, " build=%s", build );
    if (n < 0 || (size_t)n >= size - len) return -1;
    return (int)(len + n);
}

static int pr_prog_has( const char *prog, char what, const char *stage )
{
    size_t sl = strlen( stage );
    const char *p = prog;

    while (*p)
    {
        if (p[0] == what && p[1] == ':' && !strncmp( p + 2, stage, sl ) &&
            (p[2 + sl] == '\n' || p[2 + sl] == 0))
            return 1;
        p = strchr( p, '\n' );
        if (!p) break;
        p++;
    }
    return 0;
}

int pr_prog_crashed( const char *prog, const char *stage )
{
    return pr_prog_has( prog, 'B', stage ) && !pr_prog_has( prog, 'E', stage );
}

int pr_prog_ended( const char *prog, const char *stage )
{
    return pr_prog_has( prog, 'E', stage );
}

int pr_prog_fresh( const char *prog )
{
    return !prog[0] || pr_prog_has( prog, 'D', "all" );
}

/* No libc below this point: these run inside signal handlers. */

static uint64_t pr_rd64( const uint8_t *p )
{
    uint64_t v = 0;
    int i;
    for (i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static uint32_t pr_rd32( const uint8_t *p )
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

int pr_find_u64( const uint8_t *buf, size_t len, size_t from, uint64_t v )
{
    size_t off;

    for (off = (from + 7) & ~(size_t)7; off + 8 <= len; off += 8)
        if (pr_rd64( buf + off ) == v) return (int)off;
    return -1;
}

void pr_frame_scan( const uint8_t *uc, size_t len, const struct pr_frame_marks *m,
                    struct pr_frame_layout *out )
{
    size_t from = 0, off;
    int rip;

    out->mc = out->rip = out->cs = out->fx = out->fs = -1;

    /* mc_rip, confirmed by mc_addr 24 bytes before it. */
    while ((rip = pr_find_u64( uc, len, from, m->rip )) >= 0)
    {
        if (rip >= PR_MC_RIP && (size_t)rip + 16 <= len &&
            pr_rd64( uc + rip - (PR_MC_RIP - PR_MC_ADDR) ) == m->fault_addr)
        {
            out->rip = rip;
            out->mc = rip - PR_MC_RIP;
            out->cs = (int)pr_rd64( uc + rip + (PR_MC_CS - PR_MC_RIP) );
            break;
        }
        from = rip + 8;
    }

    /* FXSAVE: FCW at +0 and the marked MXCSR at +24; it sits after mc_ss when mc is known. */
    from = out->mc >= 0 ? (size_t)out->mc + PR_MC_SS + 8 : 0;
    for (off = (from + 7) & ~(size_t)7; off + 32 <= len; off += 8)
    {
        if (pr_rd32( uc + off + 24 ) == m->mxcsr &&
            (uint16_t)(uc[off] | uc[off + 1] << 8) == m->fcw)
        {
            out->fx = (int)off;
            break;
        }
    }

    /* FS base: after the 512-byte FXSAVE area when it was found, else after mcontext's registers. */
    from = out->fx >= 0 ? (size_t)out->fx + 512 : out->mc >= 0 ? (size_t)out->mc + PR_MC_SS + 8 : 0;
    out->fs = pr_find_u64( uc, len, from, m->fsbase );
}

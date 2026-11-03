/* probe_util.h: the probe's pure helpers (no libkernel, no I/O), so they can be
 * unit-tested on the host (tests/probe_util_test.c).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PROBE_UTIL_H
#define PROBE_UTIL_H

#include <stddef.h>
#include <stdint.h>

/* ---- results: an ordered key=value store, persisted as "key=value\n" lines */
#define PR_MAX_FIELDS 64
#define PR_KEY_LEN    24
#define PR_VAL_LEN    64

struct pr_results
{
    int  count;
    char key[PR_MAX_FIELDS][PR_KEY_LEN];
    char val[PR_MAX_FIELDS][PR_VAL_LEN];
};

void        pr_init( struct pr_results *r );
/* Sets (or replaces) a value; returns 0, or -1 when the store is full or the key/value is too long
 * or contains a separator (space, '=', newline). */
int         pr_set( struct pr_results *r, const char *key, const char *val );
const char *pr_get( const struct pr_results *r, const char *key );
/* Parses "key=value" lines; malformed lines are ignored. Returns the number of fields read. */
int         pr_parse( struct pr_results *r, const char *text );
/* Serialises to "key=value\n" lines; returns the length written (excluding the NUL), or -1 if the
 * buffer is too small. */
int         pr_serialize( const struct pr_results *r, char *buf, size_t size );

/* ---- the PS4WINE a line */
/* The fields the milestone a line carries, in order (docs/ps4/MILESTONES.md). */
extern const char *const pr_line_fields[];
/* "PS4WINE a hello ok build=<build> direct_mib=... cpus=..." with "-" for a field not measured.
 * Returns the length, or -1 if it did not fit. */
int pr_format_line( const struct pr_results *r, const char *build, char *buf, size_t size );
/* The milestone a gate as check.sh applies it: direct_mib >= 4000 and jit=ok. Used only to pick
 * the screen colour; check.sh on the host stays the authority. */
int pr_gate( const struct pr_results *r );

/* ---- the PS4WINE i1 line (docs/ps4/HANDOFF-i.md, "i1, the probe") */
/* The fields the i1 line carries, in order: the gated ones first, then the recorded ones. */
extern const char *const pr_i1_fields[];
/* "PS4WINE i1 lowbase direct_mib=... launches=N build=<build>" with "-" for a field not measured.
 * Returns the length, or -1 if it did not fit. */
int pr_format_i1_line( const struct pr_results *r, const char *build, char *buf, size_t size );

/* ---- progress file: "B:<stage>" / "E:<stage>" / "DONE:all" lines */
/* 1 when the stage began on an earlier launch and never ended (crashed or hung). */
int pr_prog_crashed( const char *prog, const char *stage );
/* 1 when a stage has ended. */
int pr_prog_ended( const char *prog, const char *stage );
/* 1 when the previous cycle finished (or there is no previous cycle): start fresh. */
int pr_prog_fresh( const char *prog );

/* ---- signal-frame layout scan */
/* What the probe plants before the fault and then looks for in the saved context. */
struct pr_frame_marks
{
    uint64_t rip;        /* address of the faulting instruction */
    uint64_t fault_addr; /* the address it loads from */
    uint32_t mxcsr;      /* the marked MXCSR value loaded before the fault */
    uint16_t fcw;        /* the x87 control word at the time (FXSAVE byte 0) */
    uint64_t fsbase;     /* the thread's FS base (the TCB self pointer at %fs:0) */
    uint64_t cs64;       /* expected 64-bit code selector, 0x43 on Orbis */
};

struct pr_frame_layout
{
    int mc;     /* offset of the FreeBSD mcontext in the ucontext, or -1 */
    int rip;    /* offset of mc_rip, or -1 */
    int cs;     /* value found at mc_rip + 8 (mc_cs), or -1 when rip was not found */
    int fx;     /* offset of the FXSAVE area (marked MXCSR at fx + 24, FCW at fx), or -1 */
    int fs;     /* offset of the saved FS base after the FP area, or -1 */
};

/* FreeBSD amd64 mcontext offsets (sys/x86/include/ucontext.h). */
#define PR_MC_RDI   8
#define PR_MC_RAX   56
#define PR_MC_ADDR  136
#define PR_MC_RIP   160
#define PR_MC_CS    168
#define PR_MC_RSP   184
#define PR_MC_SS    192

/* First 8-byte-aligned offset in [from, len) holding v, or -1. Signal-safe (no libc). */
int pr_find_u64( const uint8_t *buf, size_t len, size_t from, uint64_t v );
/* Locates mcontext, FXSAVE and FS base in a copied ucontext. Signal-safe. */
void pr_frame_scan( const uint8_t *uc, size_t len, const struct pr_frame_marks *m,
                    struct pr_frame_layout *out );

#endif /* PROBE_UTIL_H */

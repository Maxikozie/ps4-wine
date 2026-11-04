/* ctl_cmd.h: the command block of the ctl ELF (docs/ps4/HANDOFF-loop.md, phase 1).
 *
 * The ELF carries one 4 KiB block in .data. scripts/ps4/ctl.sh finds its 16-byte magic (exactly one
 * copy must exist in the file) and overwrites the block with dd conv=notrunc before every send, so
 * a command never travels as a file on the console and every result names its nonce. The offsets
 * below are fixed: ctl.sh writes them by number and tests/ctl_test.sh compares them with
 * `ctl.sh --print-layout` through a host build of this header.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef CTL_CMD_H
#define CTL_CMD_H

#include <stdint.h>

#define CTL_MAGIC       "PS4WINE-CTL-CMD1"  /* 16 bytes, no NUL in the block */
#define CTL_MAGIC_LEN   16
#define CTL_VERSION     1
#define CTL_BLOCK_SIZE  4096
#define CTL_NONCE_MAX   40
#define CTL_PATH_MAX    256
#define CTL_ARGS_MAX    8
#define CTL_ARG_LEN     64

enum ctl_op
{
    CTL_OP_NONE    = 0, /* the block as built: hello only */
    CTL_OP_STATUS  = 1, /* hello, libraries, the big app, AppExists: no state changes */
    CTL_OP_KILL    = 2, /* close PSWN00001 (the identity proofs first) */
    CTL_OP_INSTALL = 3, /* install pkg (PSWN00001 only, never while it runs) */
    CTL_OP_LAUNCH  = 4, /* launch PSWN00001 with args */
    CTL_OP_CYCLE   = 5, /* kill if running, install, launch */
    CTL_OP_PROBE   = 6, /* x1: cycle with every diagnostic of the plan's steps 0-7 */
};

#define CTL_FLAG_DRY 0x1 /* log every decision, change nothing on the console */

struct ctl_block
{
    char     magic[CTL_MAGIC_LEN];             /*   0 */
    uint32_t version;                          /*  16 */
    uint32_t op;                               /*  20 */
    int32_t  title_pid;                        /*  24: the title's pid from its PW_MS line, 0 unknown */
    uint32_t flags;                            /*  28 */
    char     nonce[CTL_NONCE_MAX];             /*  32: [A-Za-z0-9-], NUL-terminated */
    char     pkg[CTL_PATH_MAX];                /*  72: absolute console path of the package */
    uint32_t argc;                             /* 328 */
    char     args[CTL_ARGS_MAX][CTL_ARG_LEN];  /* 332: launch arguments, each NUL-terminated */
    char     pad[CTL_BLOCK_SIZE - 844];        /* 844 */
};

#define CTL_OFF_VERSION   16
#define CTL_OFF_OP        20
#define CTL_OFF_TITLE_PID 24
#define CTL_OFF_FLAGS     28
#define CTL_OFF_NONCE     32
#define CTL_OFF_PKG       72
#define CTL_OFF_ARGC      328
#define CTL_OFF_ARGS      332

_Static_assert(sizeof(struct ctl_block) == CTL_BLOCK_SIZE, "ctl block is 4 KiB");
_Static_assert(__builtin_offsetof(struct ctl_block, nonce) == CTL_OFF_NONCE, "nonce offset");
_Static_assert(__builtin_offsetof(struct ctl_block, pkg) == CTL_OFF_PKG, "pkg offset");
_Static_assert(__builtin_offsetof(struct ctl_block, argc) == CTL_OFF_ARGC, "argc offset");
_Static_assert(__builtin_offsetof(struct ctl_block, args) == CTL_OFF_ARGS, "args offset");

#endif /* CTL_CMD_H */

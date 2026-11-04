/* ctl_block_dump.c: read the command block out of a file the way ctl/ctl.c lays it out (ctl_cmd.h)
 * and print it, for tests/ctl_test.sh. "layout" prints the header's offsets in ctl.sh --print-layout's
 * format instead.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "ctl_cmd.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main( int argc, char **argv )
{
    static unsigned char data[16 << 20];
    struct ctl_block b;
    size_t n, at = 0, found = 0;
    FILE *f;

    if (argc == 2 && !strcmp( argv[1], "layout" ))
    {
        printf( "magic=%s size=%zu version=%zu op=%zu title_pid=%zu flags=%zu nonce=%zu pkg=%zu argc=%zu args=%zu "
                "nonce_max=%d path_max=%d args_max=%d arg_len=%d\n", CTL_MAGIC, sizeof(struct ctl_block),
                offsetof(struct ctl_block, version), offsetof(struct ctl_block, op),
                offsetof(struct ctl_block, title_pid), offsetof(struct ctl_block, flags),
                offsetof(struct ctl_block, nonce), offsetof(struct ctl_block, pkg),
                offsetof(struct ctl_block, argc), offsetof(struct ctl_block, args), CTL_NONCE_MAX, CTL_PATH_MAX,
                CTL_ARGS_MAX, CTL_ARG_LEN );
        return 0;
    }
    if (argc != 2 || !(f = fopen( argv[1], "rb" ))) { fprintf( stderr, "usage: ctl_block_dump FILE|layout\n" ); return 1; }
    n = fread( data, 1, sizeof(data), f );
    fclose( f );
    for (size_t i = 0; i + CTL_MAGIC_LEN <= n; i++)
        if (!memcmp( data + i, CTL_MAGIC, CTL_MAGIC_LEN )) { if (!found++) at = i; }
    if (found != 1) { printf( "magics=%zu\n", found ); return 2; }
    if (at + sizeof(b) > n) { printf( "truncated\n" ); return 2; }
    memcpy( &b, data + at, sizeof(b) );
    b.nonce[CTL_NONCE_MAX - 1] = 0;
    b.pkg[CTL_PATH_MAX - 1] = 0;
    printf( "version=%u op=%u title_pid=%d flags=%u nonce=%s pkg=%s argc=%u", b.version, b.op, b.title_pid, b.flags,
            b.nonce, b.pkg[0] ? b.pkg : "-", b.argc );
    for (unsigned i = 0; i < b.argc && i < CTL_ARGS_MAX; i++)
    {
        b.args[i][CTL_ARG_LEN - 1] = 0;
        printf( " arg%u=%s", i, b.args[i] );
    }
    for (size_t i = 844; i < sizeof(b); i++)
        if (((unsigned char *)&b)[i]) { printf( " pad_dirty=%zu", i ); break; }
    printf( "\n" );
    return 0;
}

/* ctl_rt.c: the two routines the compiler may call on its own (struct copies and zeroing), for
 * the plain ELF form of ctl, which links no libc. The fSELF form takes them from libc.a.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stddef.h>

void *memset( void *dst, int c, size_t n )
{
    volatile unsigned char *d = dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}

void *memcpy( void *dst, const void *src, size_t n )
{
    volatile unsigned char *d = dst;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

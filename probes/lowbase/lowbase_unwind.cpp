/* lowbase_unwind.cpp: the i1 probe's stage 11 inside lowbase.prx. A C++ throw caught in the PRX,
 * and _Unwind_Backtrace from the caller's thread. The SDK's libunwind finds its tables through
 * __eh_frame_hdr_start/__eh_frame_start, which lowbase.prx defines over its own sections
 * (third_party/prospero-win/wine/ps5/prx_eh_frame.ld), so a walk that reaches the stub's frames on
 * the main thread finds no table for them: the frame count and whether any PC fell in the
 * released range say what it did.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "lowbase.h"

#include <unwind.h>

namespace {

struct LowbaseError { int code; };

__attribute__((noinline)) void thrower( int code )
{
    throw LowbaseError{ code };
}

struct Walk { uintptr_t lo, hi; int frames, in_eboot; };

_Unwind_Reason_Code step( struct _Unwind_Context *context, void *arg )
{
    Walk *walk = static_cast<Walk *>( arg );
    uintptr_t ip = _Unwind_GetIP( context );

    walk->frames++;
    if (ip >= walk->lo && ip < walk->hi) walk->in_eboot++;
    return walk->frames >= 64 ? _URC_END_OF_STACK : _URC_NO_REASON;
}

}

extern "C" int lb_unwind_throw(void)
{
    try
    {
        thrower( 0x1b );
    }
    catch (const LowbaseError &e)
    {
        return e.code == 0x1b;
    }
    catch (...)
    {
        return 0;
    }
    return 0;
}

extern "C" int lb_unwind_backtrace( uintptr_t eboot_lo, uintptr_t eboot_hi, int *frames, int *in_eboot, int *rc )
{
    Walk walk = { eboot_lo, eboot_hi, 0, 0 };

    *rc = _Unwind_Backtrace( step, &walk );
    *frames = walk.frames;
    *in_eboot = walk.in_eboot;
    return walk.frames > 0;
}

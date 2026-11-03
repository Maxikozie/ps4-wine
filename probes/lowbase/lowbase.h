/* lowbase.h: milestone i1's probe (docs/ps4/HANDOFF-i.md, "i1, the probe"), shared between the
 * PRX's C and C++ parts. The stub eboot (stub.c) loads lowbase.prx, which releases the eboot's
 * segments and runs the stages; nothing here is used by the stub.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef LOWBASE_H
#define LOWBASE_H

#include <setjmp.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LB_DIR      "/data/ps4-wine/lowbase"
#define LB_PROGRESS LB_DIR "/progress.txt"
#define LB_RESULTS  LB_DIR "/results.txt"
#define LB_LOG      LB_DIR "/probe.log"

/* lowbase_rt.c: logging (netlog + fsync'd probe.log; klog on request), results and progress,
 * the stage guard, the screen. */
void lb_say( const char *fmt, ... ) __attribute__((format(printf, 1, 2)));
void lb_say_k( const char *fmt, ... ) __attribute__((format(printf, 1, 2)));
void lb_emit_line( const char *line );
void lb_log_open(void);
uint64_t lb_now_us(void);

void lb_set( const char *key, const char *fmt, ... ) __attribute__((format(printf, 2, 3)));
void lb_set_rc( const char *key, int rc );
const char *lb_get( const char *key );
void lb_results_line( char *buf, size_t size, const char *build );
/* Progress: returns the number of launches in this cycle (1 on a fresh one). */
int lb_prog_load(void);
void lb_prog_mark( char what, const char *id );
int lb_prog_crashed( const char *id );
void lb_prog_done(void);

/* The guard: a fault inside lb_guarded() lands back in it (longjmp from a frame the handler
 * builds), and the stage records where. The handler is libkernel's exception API, installed once
 * before the release; stage 12 tests FreeBSD sigaction on its own. */
typedef void (*lb_stage_fn)(void);
void lb_guard_install(void);
/* Runs fn under the guard; returns 0, or the signal number of a fault it caught. */
int lb_guarded( lb_stage_fn fn, uint64_t *fault_rip, uint64_t *fault_addr );
extern volatile int lb_faults_unresolved;

/* The screen: VideoOut through 2 direct-memory buffers (probe.c's screen_open/screen_show). */
int lb_screen_open( int *rc_out );
int lb_screen_show( uint32_t color );
int lb_screen_close(void);
#define LB_GREEN 0xFF00C040u
#define LB_BLUE  0xFF2040E0u
#define LB_RED   0xFFD01010u

/* lowbase_unwind.cpp, stage 11. eboot_lo/hi: the released range. */
int lb_unwind_throw(void);                     /* 1 when the throw was caught */
int lb_unwind_backtrace( uintptr_t eboot_lo, uintptr_t eboot_hi, int *frames, int *in_eboot, int *rc );

#ifdef __cplusplus
}
#endif
#endif

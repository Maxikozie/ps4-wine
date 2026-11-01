# Hand-off: phase p (performance and audio, before milestone g)

Written 2026-11-01, after milestone f passed (repo `13ddea7`, fork `73a9a10`). Read `CLAUDE.md`,
then this, then `MILESTONES.md` (the p note and table, the g row and note), `HANDOFF-f.md` (plan
`f`, "Games on the host", the native readiness notes that became p2) and the last lines of `LOG.md`.

## Resume here (2026-11-01 22:15: p6 PASSED, phase p done; p5 and e still pass on keep)

**Phase p is complete:** p1-p6 and p5w passed. Next is milestone g (Bloodlines).

**p6's console results** (LOG.md 22:03-22:13; one package, `ps4-wine-dd2ce32+dirty-p6.pkg`; launches set by
env.txt only):

| Launch | Result |
|---|---|
| L1 p6, `floor` | FAIL as planned, on `hold_flex_kib` only (49152 KiB for 8) |
| L2 p6, `keep` | **PASS** |
| L3 p5, default (keep), recorded | **PASS** |
| L4 e, default (keep), recorded | **PASS** |
| L5 p6, `WINE_PS5_WOW64_CPU=wow64native.dll` (keep) | **PASS** on the native CPU (`cpu=native`, caps 7): all 23 cases, both holds at 0 KiB, 33 threads kept. Window callbacks on new threads were tested on the native CPU for the first time (p5w and L2 ran on the translator) |

**L1, the floor (today's path): reuse, not a leak.**
- When the first 8 threads ended, none of their flexible memory came back (`hold_back_kib=0`).
- The second 8 cost 0 KiB (`hold2_flex_kib=0`): libthr hands the cached stacks to later threads.
- `stack_probe`, a single joinable thread joined twice, took 16384 KiB a round and kept it. My reading,
  from FreeBSD libthr's source, not measured: one dead thread is below libthr's collection threshold of
  5, so it was not reused.
- So the floor's cost is the peak number of live floor threads times 16 MiB, never given back.

**L2, keep: libkernel accepts Wine's own stacks.**
- `PW_WINE64 thread_stack asked=keep policy=keep`; `threads_kept=33`, `threads_keep_refused=0`.
- Patch 1100 logged no `thread frame moved` line: the threads ran on their kernel stacks.
- Both sets of 8 cost 0 KiB of flexible memory. Free flexible memory was 270 MiB at the hold (L1: 158).
- All 23 window cases passed: this is the p5w recheck.

**L3, p5 on keep:**
- `underruns=0`, 2131 non-silent grains, the HDMI tail at -12.8 dB mean; the segment unchanged.
- Pinball's 3 threads were kept. Free flexible memory was 300 MiB at the line, against 252 MiB on the floor.

**L4, e on keep:**
- 600 frames; the HDMI frame at 36 s as in the earlier passes.
- All 9 of ntdll's threads were kept.
- libvulkan.prx's own copy of the layer created 6 threads (RADV's) and raised all 6. Its floor resolved
  to **16384 KiB**, not the 1 MiB a Wine thread's kernel stack could have set, so RADV's threads still
  take ~96 MiB.
- Free flexible memory went from 431 to 270 MiB.
- One scan-out copy of 292.8 ms (earlier runs had one of 125 and 161 ms; not investigated).

**Built after L2, before L3** (runtime only, `runtime.sh --prx-only`, no reinstall):
- `orbis::threadStackFloorPeek` was added to patch 0001, and `pw_wine_thread_stats` and
  `pw_vulkan_thread_stats` now read the floor with it.
- Why: under keep, no ntdll thread resolves the floor, so the title's read resolved it from its own
  2 MiB thread (L2 printed `stack_floor_mib=2`; no thread was affected).
- `stack_floor_mib=0` now means "not resolved". The package's title still links patch 0001 without the
  peek, which changes nothing there.

**Next:**
1. The user commits, fork and repo.
2. Milestone g, starting with its plan: g's planning question is whether to build a desktop host Wine to
   play Bloodlines to the first map on the laptop.
3. Not run, by the user's choice: p6 with `PS4WINE_EXE=C:\wincb64.exe` (64-bit threads).

**Open for g, from p6's numbers:**
- **Peak live threads and threads created:** the first Bloodlines runs report both. Live threads come from
  Wine's own `nb_threads` (`ntdll/unix/thread.c`), since a kept thread no longer runs orbis-compat's
  trampoline.
- **Unix-only threads still take their module's floor**, at 16 MiB each and reused, not returned: RADV's
  6 (about 96 MiB) and the main Wine thread's 16 MiB stack.
- **The rest of the pool:** with keep, about 129-160 MiB of flexible memory is still used by other things
  at Wine start (431 → 270-300 MiB). Not measured further.
- **Small fallback:** keep is in force, so the warning about small without reuse (threads created over a
  session) does not apply unless keep is refused.

## Before the console runs: p6 built and host-tested (2026-11-01 22:00)

**p6, the thread stacks, is the gate for g.** p1-p5 and p5w passed; p6 was built and host-tested before
its first console run.

**Cause** (source read, `refs/orbis-compat/src/orbis_thread.cpp:351-423`):
- ntdll.prx links orbis-compat's `pthread_create` interposer, which looks only at the requested size.
- Wine's `spawn_thread` sets its 1 MiB kernel stack with `pthread_attr_setstack`. Direct memory in Wine's
  range at `0x1000000000`, guard 0.
- 1 MiB is below the floor, which is 16 MiB: the size of the first thread that resolved it, Wine's main
  thread. So the interposer builds a fresh attr that keeps only the detach state and the guard size.
- libkernel then maps a 16 MiB stack out of flexible memory: ~12 MiB each, measured in p5w.

**Built (uncommitted; the user commits):**
- Repo:
  - `patches/orbis-compat/0001-thread-caller-stack-policy.patch` (MIT, as the files it changes). When the
    attr carries a stack address, `orbis::threadCallerStackPolicy` decides:
    - **keep (default):** the attr goes to `scePthreadCreate` untouched, without the trampoline (its 64 KiB
      alt array would sit at the top of Wine's kernel stack; Wine sets its own alt stack in
      `init_thread_pipe`). A refusal is counted (`threads_keep_refused`), logged once, and falls back to
      small.
    - **small:** a fresh 512 KiB stack, with the trampoline.
    - **floor:** the old behaviour.
    - Requests without a stack address are unchanged.
  - `build.sh compat` clones `refs/orbis-compat` into `build/src/orbis-compat` at `ORBIS_COMPAT_COMMIT`
    (`common.sh`), applies `patches/orbis-compat/*.patch` (stamped, as `mesa_patch`), builds from the clone,
    and stages its `include/`.
  - `check.sh p6`, `tests/check_p6_test.sh` and 5 fixtures (in `probe-test`). The p5w, p5 and e fixtures
    carry the new fields.
  - MILESTONES: the p6 row, g's note, and the vo1080 polish item. THIRD_PARTY rows 28, 69, 75 and 76.
- Fork:
  - `wine/orbis/pw_wine_threads_orbis.c` exports `pw_wine_thread_policy(name)` and
    `pw_wine_thread_caller_stacks(...)`.
  - `wine/orbis/pw_vulkan_radv_orbis.c` exports `pw_vulkan_thread_stats` (libvulkan.prx's own copy of the
    layer: created, raised, floor). The floor is read only when libvulkan created a thread, since reading
    it resolves it.
  - Title:
    - `wine64_main_orbis.c` hands env.txt's `WINE_PS5_THREAD_STACK` to ntdll right after ntdll.prx loads
      (log line `PW_WINE64 thread_stack asked=.. policy=..`).
    - `pw_milestone_orbis.c` has plan **p6** with stages `stack_probe`, `wow_bind`, `display`, `wincb`.
    - New fields on the p5, p5w, p6 and e lines: `stack_policy threads_kept threads_small
      threads_keep_refused`.
    - The hold probe now takes 5 samples, adding `hold_back_kib` and `hold2_flex_kib`.
    - The e line also gets ntdll's thread fields and libvulkan's: `vk_threads_created vk_threads_raised
      vk_stack_floor_kib`.
    - `PW_STAGE_FIELDS` is 1024.
  - `tests/wine_wincb.c`: the 8 hold threads come twice (`WINCB hold2 n=`, `hold2_end`, `hold2_windows`).
  - `tests/lab/pw_foreign_stack.c`: `PW_FOREIGN_STACK_KIB`.
  - `tests/test_wine_wincb.py`: both rounds checked everywhere; new case, the shim at 512 KiB with 1100.
- `stack_probe` (title only, before Wine): a joinable thread with libkernel's own 16 MiB stack (guard 0, the
  shape the floor gives Wine's threads), through `scePthreadCreate`, sampled alive, joined, twice. The fields
  are `sp_lib_rc`, `sp_lib_alive1_kib`, `sp_lib_kib1`, `sp_lib_alive2_kib` and `sp_lib_kib2`: libkernel's
  reuse without Wine. It reserves nothing at Wine's base.

**The rule, fixed before the first p6 launch** (`check.sh p6`): p5w's rule plus `threads_create_failed=0
hold_flex_kib<=8192 hold2_flex_kib<=8192`.
- 8192 KiB is 8 live threads at 1 MiB each: twice the small policy's 512 KiB, leaving room for libkernel's
  thread object, TLS and the 16 KiB granule. 60 threads would then take at most 60 MiB of the ~431 MiB pool.
- The floor's 98304 fails it twelvefold.
- Recorded, not gated: `stack_policy`, `threads_kept/small/keep_refused`, `hold_back_kib`, `sp_lib_*`, and
  e's `vk_*`.
- The host count of Bloodlines' threads was dropped from this step (the user, 2026-11-01): either fix
  brings a thread to about 0 or 512 KiB, so 30 or 60 threads both fit.

**Next, one package, runtime and prefix, launches by env.txt only:**

| # | env.txt | Decides |
|---|---|---|
| L1 | `PS4WINE_MILESTONE=p6 WINE_PS5_THREAD_STACK=floor` | today's path: reuse or leak at Wine's level (`hold2_flex_kib` about 0 = reuse, about 98304 = leak; `hold_back_kib`) and at libkernel's (`sp_lib_*`). Expected FAIL on `hold_flex_kib` (the baseline) |
| L2 | `PS4WINE_MILESTONE=p6 WINE_PS5_THREAD_STACK=keep` | the fix. libkernel accepted Wine's stack if `threads_keep_refused=0` and patch 1100 logs no `thread frame moved` line (its silence shows the threads ran on their kernel stacks). Expected PASS |
| L3 | `PS4WINE_MILESTONE=p5`, recorded | sound, the segment, `flex_mib` against 252 |
| L4 | `PS4WINE_MILESTONE=e`, recorded | DXVK and RADV with kept stacks; `vk_stack_floor_kib` (whether a Wine thread on a 1 MiB kernel stack set libvulkan's floor) |
| (L5) | p6 + `PS4WINE_EXE=C:\wincb64.exe` | 64-bit threads |
| (L6) | p6 + `WINE_PS5_WOW64_CPU=wow64native.dll` | new threads on the native CPU |

- If L2 shows `threads_keep_refused>0`, small becomes the default. That is one word in the patch, then
  `build.sh compat`, `build.sh wine --skip-host` and `runtime.sh --prx-only`. L3 and L4 run on it.
- The p5w recheck is L2: the same wincb32.exe and 23 cases, and p6's rule contains p5w's.

**For g** (from this step):
- The first Bloodlines console runs report **peak live threads** and **threads created over the session**.
  - Live threads come from Wine's own `nb_threads` counter (`ntdll/unix/thread.c`). A thread whose caller-set
    stack is passed through no longer runs orbis-compat's trampoline, so orbis-compat does not see it live.
  - If the small fallback is in use and stacks are not reused, threads created over a 30-minute session is
    the number to watch.
- Unix-only threads (RADV's in libvulkan.prx, the in-process server's) still take their module's floor. If
  L1 shows that floor stacks leak, those are a leak to watch too. L4's `vk_stack_floor_kib` says what floor
  RADV's threads got.
- Whether g needs a desktop host Wine (X11, PulseAudio: none of the fork's host trees has either) to play to
  the first map on the laptop is g's planning question, not p6's.

**Not tested:** a long run, hand play with sound, Bloodlines' real thread count, suspension of and faults in
system calls on kept-stack threads.

## Earlier: p5 PASSED, phase p's steps done (2026-11-01 21:20; e still passes after 1100)

**p1-p5 and p5w passed.** Next was milestone g (Bloodlines), but first the thread stacks' cost (below: "The
root fix for the stack cost"), which became p6 above.

**p5's underrun count, as this plan defines it** (built after the 21:00 run):
- Code: fork `src/pw_audio_mix.h` (`PwAudioStarve`, unit-tested in `tests/test_pw_audio_mix.c`),
  `wine/wineps5/unix.c` (exported as `pw_wineps5_stats`, each underrun logged on `err:ps5audio`),
  and the title's p5 line.
- Per stream, the driver counts the grains in which a started stream's ring ran out. It sorts each
  stretch of them by how the stretch ends:
  - more data while the stream is still started: an **underrun** (silence inside a sound);
  - a stop or reset: a **drain** (the sound's end; winmm stops its client only after the last block).
- New fields:

  | Field | Meaning |
  |---|---|
  | `underruns`, `underrun_grains` | the plan's underruns and their grains (gated: `underruns=0`) |
  | `drains`, `drain_grains` | sound ends |
  | `starved_grains`, `mixed_grains` | all short grains; all grains mixed |
  | `audio_stats` | `ok`, or why the driver's counts are missing |
  | `gaps`, `gap_max_us` | the title's old count of pauses between grains, renamed; recorded only |

**Launches 21:15 and 21:18 (LOG.md), one package (`ps4-wine-0cb4675+dirty-p5u.pkg`), env.txt only:**

| Launch | Result |
|---|---|
| L4 p5 | **PASS**: `underruns=0`, 14 drains (53 grains), 12 gaps (largest 674 ms, the mixer idle between sounds); 2130 non-silent grains, 1208 in the tail; HDMI tail -13.3 dB mean; the segment as before |
| L5 e | **PASS** (HDMI frame t=37 s: 960,540 = 255,255,16, 240,135 = 2,0,247): DXVK's and RADV's worker threads make their system calls on Wine's 1 MiB kernel stacks for the first time; 600 frames, no hang, `ms_avg` 16.7 ms |

L5 also had one 125 ms scan-out copy; the 14:48 pass had one of 161 ms, so it is not new.

## Earlier: p5w passed, p5 failed on its first underrun counter (2026-11-01 21:05)

**Console results (LOG.md 20:55, 20:56, 21:00), one package and one runtime, env.txt only:**

| Launch | Result |
|---|---|
| L1 p5w, `WINE_PS5_THREAD_FRAME=0` | FAIL as predicted: main thread 9/9, new threads 0/14, `cbt_new=0`, direct and cross ok; the console logged `KeUserModeCallback callback 4 refused: stack 0x7e83b2d38 is not above the kernel stack 0x100be20000+0x2000`; `+syscall`: `UserCall` from the main thread only |
| L2 p5w, 1100 on | **PASS**: 23/23, every probe; `thread frame moved to the kernel stack (stack 0x7e83b3e58, kernel stack 0x100be20000)` |
| L3 p5, 1100 on, recorded | FAIL on `underruns=13` only (see below) |

**L3 in detail:**
- **Pinball plays sound on the PS4.** The user heard the intro and then everything: 2131 non-silent
  grains, 1209 in the tail. The HDMI tail window averages -12.7 dB against the -30 dB rule.
- **The segment is unchanged** (shown_hz 59.9, copy 0.95 ms, guest 0.225 ms, 0 faults), which is
  the regression check for 1100.
- **Why it still fails:** the underrun counter (`pw_ms_audio`, `pw_milestone_orbis.c` ~1555) counts
  any gap of 2 grains to 1 s between two `sceAudioOutOutput` calls. That is not this plan's
  definition (step 3 under p5: a grain sent as silence while a stream is open and the ring is
  empty). A pause between effects with no stream open counts too, so whether the 13 (largest gap
  576 ms) are real dropouts is not measured.

**The thread stacks' cost (the user's addition):**
- The floor is 16 MiB, and every Wine thread is raised to it (25 in p5w, 3 in p5).
- 8 live threads took 98304 KiB of flexible memory, 12 MiB each, the same with and without 1100.
- Free flexible memory was 431 MiB before Wine and 110 MiB with p5w's threads alive. It was still
  110 MiB after they ended: the memory does not come back.
- Pinball with audio ends at 252 MiB.
- So at about 12 MiB a thread, the ~110-250 MiB left allows only some 10-20 more threads. **That is
  a wall for g**, which runs many more threads than Pinball.

**Next:**
1. The user commits, fork and repo (p5w passed).
2. **p5's underruns:** make the counter match the plan's definition: the driver or sink reports a
   silent grain sent while a stream is open and its ring is empty. Log each underrun (time, gap,
   stream open, segment or tail) and rerun p5. The rule stays `underruns=0`.
3. **The root fix for the stack cost, before g:** orbis-compat's interposer keeps a caller's attr
   when it carries a stack address. That is a patch to orbis-compat (MIT), applied by
   `build.sh compat`; Wine's threads would then run on their 1 MiB kernel stack.
   - First measure whether libkernel accepts a stack inside Wine's reserved range: a title probe,
     before the patch.
   - The p5w/p5 thread fields (`hold_flex_kib`, `threads_raised`, `flex_mib`) are its baseline;
     1100 stays (it does nothing on threads that run on their kernel stack).
4. **Not tested:**
   - `wincb64.exe` on the console (`PS4WINE_EXE=C:\wincb64.exe`);
   - p5w on the native CPU;
   - suspension of, and faults inside system calls on, new threads (both changed by 1100:
     `is_inside_syscall` now holds on them);
   - a long run;
   - hand play with sound.

## Earlier: p5w built (2026-11-01 20:50, before the console runs)

**Cause (from the source and the 19:38 log; reproduced and fixed on the host before the console):**
- winmm's devices thread's "Message" window is aborted because no window procedure runs at all on a
  new thread. The builtin class's procedure is user32's `MessageWndProc` (TRUE for WM_NCCREATE),
  reached through `KeUserModeCallback`, not win32u's default procedure.
- ntdll.prx links orbis-compat's `pthread_create`. It replaces any requested stack below its floor
  (the main thread's size, 16 MiB here) with a fresh attribute that keeps only the detach state and the
  guard size, so the 1 MiB kernel stack `spawn_thread` passes with `pthread_attr_setstack` is dropped.
- A new thread's syscall frame is therefore made on that foreign stack (0x7e7xxxxxx, below the kernel
  stack at >= 0x1000000000), and `KeUserModeCallback`'s check (`kernel_stack + 0x2000 > &frame`)
  refuses every callback with `STATUS_STACK_OVERFLOW`, before any trace. That covers window
  procedures, hooks, WM_GETMINMAXINFO and WM_NCCREATE, on every thread but the main one, on any CPU
  backend, in 32 and 64 bit.
- The 19:38 log fits: 002c's win32u locals at 0x7e719bxxx, the main thread's at 0x100010fxxx, thread
  stacks 16 MiB apart, no `err:seh`. The "syscall 0x43 came back replaced" lines are NtContinue at
  thread start (harmless).

**Built for p5w (uncommitted; the user commits):**
- Fork `tests/wine_wincb.c` (`wincb32.exe`/`wincb64.exe`): 23 window cases (main/new thread x
  HWND_MESSAGE/hidden top-level x builtin "Message"/own class, ANSI and Unicode, DefWindowProc, USER
  calls first, two windows in a row) plus probes:
  - direct `CallWindowProcW` (no kernel callback);
  - a per-thread CBT hook;
  - a new thread's send to a main-thread window;
  - 8 threads alive at once while the title samples the flexible memory.
- Fork `tests/lab/pw_foreign_stack.c`: an `LD_PRELOAD` `pthread_create` that moves every thread with
  a caller-set stack onto a 16 MiB stack below it, as the PS4 does.
- Fork `wine/patches/1100-ntdll-orbis-new-thread-syscall-frame-on-kernel-stack.patch`:
  - a thread found off its kernel stack gets its frame at that stack's top, as the first thread does;
  - `WINE_PS5_THREAD_FRAME=0` keeps the old placement;
  - the first such thread logs `thread frame moved to the kernel stack (stack .., kernel stack ..)` or
    `thread frame left in place (switch off; ...)`;
  - `KeUserModeCallback` logs its first refusal.
  - It is a runtime condition, not an `__ORBIS__` gate, so it does nothing on the PC unless threads
    are moved.
- Fork `tests/test_wine_wincb.py` (in `make test`) on the host, 32 and 64 bit:

  | Host run | Result |
  |---|---|
  | installed Wine | every HWND_MESSAGE case on every thread; top-level refused on both threads (headless) |
  | user driver + translator | all 23 and every probe |
  | + shim + 1100 | all 23 |
  | + shim + `WINE_PS5_THREAD_FRAME=0` | the PS4's failure exactly: new_ok=0/14, cbt_new=0, hold_windows=0, the main thread's 9/9, direct and cross ok, the refusal line |

  The fork's `wine_fiber_stacks` test agrees: it fails under the shim on the unfixed Wine
  (`thread-growth callback=0`) and passes on the fixed one.
- **The thread stacks' cost** (the user's addition): ntdll.prx exports `pw_wine_thread_stats`
  (`wine/orbis/pw_wine_threads_orbis.c`, orbis-compat's `threadCounts`/`threadFailures`/
  `threadStackFloor`). The p5 and p5w lines carry:
  - `flex_mib_start` (before Wine) and `flex_mib` (at the line);
  - `threads_created`, `threads_raised`, `threads_create_failed`, `stack_floor_mib`;
  - p5w also `hold_flex_kib` (what 8 live threads took), `flex_mib_hold` and `threads_created_hold`.
  - Recorded, not gated.
- Title: plan `p5w` (`wow_bind`, `display`, `C:\wincb32.exe`; before p5 in `plans[]`, so p5 stays
  the default); env.txt `PS4WINE_EXE` replaces any plan's program (`C:\wincb64.exe`).
- Repo:
  - `prefix.sh` builds and uploads both exes;
  - `check.sh p5w` (rule written before the first run: `main_ok` and `new_ok` all made,
    `direct_main=1 direct_new=1 cbt_main>=1 cbt_new>=1 cross=ok exit=0 faults_unresolved=0`);
  - `tests/check_p5w_test.sh` + 4 fixtures;
  - the p5 fixtures carry the new fields.

**Next, one package, launches by env.txt only:**
- **L1:** `PS4WINE_MILESTONE=p5w`, `WINE_PS5_THREAD_FRAME=0`, `WINEDEBUG=...,+syscall`. Expected
  FAIL in the pattern above, with the "left in place" and "refused" lines.
- **L2:** the same without the switch. Expected PASS.
- **L3:** `PS4WINE_MILESTONE=p5`, recorded: Pinball's sound, and the segment fields as the regression
  check for a change that touches every Wine thread.
- **(L4)** `PS4WINE_EXE=C:\wincb64.exe` on p5w.

**Root fix for later (not built):** orbis-compat's interposer could keep a caller's attr when it
carries a stack address (its own comment says a caller that chose its own stack wants no
interference). That would be a patch to orbis-compat (MIT) applied by `build.sh compat`; Wine's
threads would then run on their 1 MiB kernel stack with no 16 MiB pthread stack. Unmeasured: whether
libkernel accepts a stack inside Wine's reserved range. The p5w/p5 thread-stack fields are its
baseline.

## Earlier: p5's first four launches (2026-11-01 19:45, blocked on the window-creation bug)

**p5 so far (LOG.md 19:34-19:45, four launches, all FAIL `grains_nonzero=0`):**
- **The port works:** `sceAudioOutOpen` with the SYSTEM user 0xFF opens at once (handle 0x20000007);
  milestone a's 0x809b0001 was the initial user. Explained and confirmed.
- **The driver works:** `wineps5.prx` (now built by `build_wine_orbis.sh`) loads, mmdevapi selects it
  ("priority Preferred", device `0,ps5`, 48 kHz stereo), the title's sink is set. The driver's name
  stays `ps5` (patch 0120's default): renaming to `orbis` as ARCHITECTURE §4.11 says would change
  nothing that works.
- **What fails:** Pinball's `waveOutOpen` starts winmm's devices thread, whose
  `CreateWindowW("Message", HWND_MESSAGE)` is aborted by WM_NCCREATE (the window procedure answers 0;
  `+win` trace: window 0x10052 made under the message parent, then "aborted by WM_NCCREATE"). So
  waveOutOpen fails, Pinball retries (one thread per try), no stream starts, no grain is played.
- **Not the translator:** the same on the native CPU (19:45). On the PS4, a window procedure called
  on a freshly created 32-bit thread answers WM_NCCREATE with 0; Pinball's main thread is fine.
- **Suspects:** the user-mode callback (KeUserModeCallback into the 32-bit side) on a new thread, or
  patch 0910 (fresh worker threads cache the desktop's handles without USER initialization).
- **Next:** a minimal 32-bit program (a message-only window on the main thread, then on a new
  thread, the WM_NCCREATE result logged) on the host and on the console, to split the two suspects
  without Pinball.

**Fixed before p5's first run (thresholds):** G = 10 non-silent grains (Pinball's shortest effect,
SOUND112.WAV, 58 ms = 10.9 grains); the HDMI rule on the mean, not the peak: the tail's window
>= -30 dB (two silent recordings of the stick: -39.5 and -36.9 dB mean, peaks -25.9 and -19.5);
the rate gate's branch is p4's (passed): `shown_hz>=59` on vo720 async; no audio-off launch needed.
New tooling: `view.sh --record` writes the stick's sound beside the video (`X.wav`, pw-record);
`check.sh p5 --audio WAV --audio-window S:D | --no-audio`; `tests/check_p5_test.sh`.

## Earlier: p2 (2026-11-01 19:17)

**p2 passed** (LOG.md 19:17): Space Cadet Pinball's 32-bit code ran natively on the PS4 for the whole
segment: `native_caps=7 cpu=native faults_unresolved=0`, 3597 presents in 60 s. Three launches:

| Launch | Result |
|---|---|
| 18:56 | FAIL by design: the title's `native_probe` stage measured everything 0883 needs (`probe_caps=7`); no Orbis provider yet |
| 19:13 | FAIL on the title's `cpu` field only (`nosym`: it asked the translator, not loaded through Wine, before looking for wow64native); the run itself was native, caps 7 |
| 19:17 | **PASS**, the cpu field fixed |

Guest time per present on the native CPU: 0.168 ms average (CPU 0.175 ms) against 0.21-0.22 ms on
the translator (p1): recorded, not gated, as the plan says.

**Built for p2 (uncommitted; the user commits):**
- Fork:
  - `wine/patches/1090-ntdll-orbis-native-wow64-signal-entry.patch`: 0883's and 0903's 13 PS5-only
    gates widened to `__ORBIS__`; libkernel found as the module whose code holds getppid's stub (the
    PS5's handle 0x2001 is not assumed); the caps stay 0 unless the main thread's alternate stack is
    in place with its TEB at the 64 KiB-aligned base (`PW_NATIVE_ALTSTACK`); the provider line
    logged once on the err channel (`PW_NATIVE_PROVIDER`).
  - `wine/wow64native/unix.c`: its PS5 gates take `__ORBIS__`; `tools/build_wine_orbis.sh` builds
    `wow64native.prx` (emulated TLS, ntdll its import source) and exports
    `__wine_prospero_native_wow64_caps` from `ntdll.prx`.
  - the title: plan `p2` (stages `wow_bind`, `display`, `native_probe`, `pinball`), the probe stage,
    `WINE_PS5_WOW64_CPU=wow64native.dll` in p2's environment, `native_caps` and `cpu=native` in
    the p lines.
- Repo: `build.sh wine` builds `wow64native.dll` (`tools/build_wow64native.sh` into
  `.deps/wow64native`); `runtime.sh` and `prefix.sh` stage it (runtime x86_64-windows, prefix
  system32); `check.sh p2`, `tests/check_p2_test.sh` + 7 fixtures; CLAUDE.md's sigaltstack trap.
- Host tests: fork `make test` exit 0 (after the user freed `/tmp`: 14 GB of milestone f's host
  runs had filled the tmpfs); `build.sh probe-test` exit 0.

**Not tested on the native CPU:** guest faults through the native entries (SEH, access
violations, illegal instructions), several guest threads doing real work, thread suspension, a long
run, hand play. For g: Bloodlines' profile can name the native CPU (MILESTONES g note); the
translator stays the fallback (0614).

**Next (then):** the user commits; then p5 (audio on sceAudioOut).

## Earlier: p1, p3, p4 (2026-11-01 18:40)

**p3 passed on `vo720`** (LOG.md 18:31) and **p4 passed** (18:40), both checked over HDMI on the
recording of the launch. Five launches of the p3/p4 package in all (LOG.md 18:21-18:40):

| Launch | Path | Result |
|---|---|---|
| 18:21 p3 | vo540: 960x540 A8R8G8B8 | FAIL: `sceVideoOutRegisterBuffers` 0x80290005 at pitch 960 and 1024. VideoOut refuses 960x540 (as it refused 2160p in a); the display never opened |
| 18:28 p3 | vo720 | FAIL, not a measurement: the 18:21 launch's progress file (closed before its last stage ended) was resumed |
| 18:31 p3 | vo720: 1280x720 A8R8G8B8, 1280x720 desktop, one row copy | **PASS**: VideoOut scales the 720p buffer to the 1080p output (pattern at 1.5x on HDMI); copy 0.92 ms (p1: 12.94, T3: 11.65) |
| 18:36 p3 | vo1080: 1920x1080 A8R8G8B8, CPU 2x by rows | FAIL: copy 111.9 ms: each row was copied to the next one by reading it back out of the write-combined scan-out buffer. A fault of the code (fixed in the source since, not re-run), not of 1080p buffers; the format shows correctly |
| 18:40 p4 | vo720, 3 buffers, async flip | **PASS**: 59.9 flips shown/s for 59.9 presents/s, no flip error; but every present waited for a free buffer |

What p3 and p4 say:
- **The copy is gone as a cost:** 0.92 ms instead of 12.94 ms per present, by letting VideoOut scale a
  1280x720 buffer. The desktop for this path is 1280x720 (`WINE_PS5_DESKTOP`); Pinball's window is
  the same size, with more black around it.
- **The time saved went to the vblank wait** (flip 15.5 ms in sync). In attract mode Pinball presents
  again ~0.2 ms after a present returns, so it is held by the display at 59.9/s whatever the present
  path: sync waits in `IsFlipPending`, async in the slot wait (`slot_waits` = every present). As the
  review predicted: p4's gain (no missed vblanks, a present that returns early) shows only when the
  guest itself needs most of a frame. Attract mode does not.
- **Formats:** A8R8G8B8_SRGB shows the driver's B,G,R,X (alpha 0) correctly at 1280x720 and 1920x1080.
- **For g:** none of this touches DXVK's path (`wsi_orbis.c`). For GDI games, `vo720` with async is
  the faster sink; neither is the title's default yet (plan f still uses the scale path).

**Changed since the plan (2026-11-01):**
- `vo540` is replaced by `vo720` (1280x720 buffers, 1280x720 desktop, VideoOut scales) and `vo1080`
  (1920x1080 buffers, no swizzle, CPU 2x). The user chose to test both.
- The p3/p4 lines are `PS4WINE p3|p4 bench pinball ...` with `present_path=`, `present_mode=`,
  `buffers=`, `shown_hz=`, ... fields; the rules read the fields (`check.sh p3`: `present_path` in
  vo720,vo1080, `vo_register=ok`, `vo_flip=ok`, `copy_us_avg<=11647`; `check.sh p4`:
  `present_mode=async`, `buffers=3`, `shown_hz>=59`, `flip_errors=0`; both the HDMI pattern, given as
  `--shot` from the recording).
- The pattern follows the desktop: 960x540 (scale, vo1080) or 1280x720 (vo720), green on the centre,
  orange on (w/8, h/8), so full-screen it lands on 960,540 and 240,135.
- After a launch closed before its last stage, the next launch resumes that cycle (18:28): move
  `/data/ps4-wine/<plan>/progress.txt` aside first, or let the resumed launch close the cycle.

**Fixed in the source after the runs (not yet on the console):** `vo1080` widens each row in cached
memory and writes it twice; the guest CPU read happens before the async slot wait (the p4 line's
`guest_cpu_us_avg=465` counted the wait's polling; guest wall time was 0.22 ms).

**p2's probe (2026-11-01 18:56, LOG.md): `probe_caps=7`.** Everything 0883 relies on works on this
PS4: the getppid stub's shape (by bytes) and its syscall instruction; `sigaltstack` both through
libkernel and as syscall 53; a SIGUSR2 registered with the kernel's own `sigaction` (416) and
`SA_ONSTACK` arrives once, on the alternate stack, where 0883's 64 KiB round-down finds the marker;
the frame holds the marked MXCSR at ucontext+320+24 and the FS base at +1152. The old "sigaltstack
returns -1" was the SDK's musl `stack_t` (`ss_size` and `ss_flags` swapped, `SS_DISABLE` 2 instead
of FreeBSD's 4), documented in orbis-compat's `signal.h`; the fork's `wine/orbis/include` has had
FreeBSD's layout since c (`abee8ea`), so Wine's `init_thread_pipe` call has probably worked since
then (its return is ignored and was never logged). Next: the Orbis variant of 0883/0903 and the
`wow64native` backend for Orbis.

## Earlier: p1 done (2026-11-01 18:06)

**p1 passed**: three passing launches of one package (LOG.md 18:00, 18:03, 18:06,
`ps4-wine-73a9a10+dirty-p1b.pkg`, plan `p1` the title's default, env.txt empty). A first launch at 17:55
measured the same but FAILed its check: the line lost everything past 512 bytes (below).

Pinball's attract mode, per present, the three launches' averages (p95 in brackets):

| Metric | 18:00 | 18:03 | 18:06 | Spread s |
|---|---|---|---|---|
| copy (swizzle + scale) | 12940 µs (13100) | 12945 (13100) | 12939 (13100) | 0.05 % |
| flip wait | 2813 (4100) | 2481 (4000) | 2813 (4100) | 12.3 % (p95: 2.5 %) |
| keep (`last_drawn`) | 690 (900) | 1034 (1200) | 690 (900) | 42.7 % |
| guest | 218 (400) | 211 (400) | 217 (400) | 3.3 % |
| guest CPU | 225 | 218 | 225 | 3.1 % |
| frame (entry to entry) | 16682 | 16691 | 16682 | 0.05 % |
| present (entry to exit) | 16463 | 16479 | 16464 | 0.1 % |
| presents in 60 s | 3597 | 3595 | 3597 | 0.06 % (0.033 Hz) |

What p1 says:
- **The copy is the cost.** 12.9 ms of the 16.5 ms present is the swizzle and the 2× scale, every
  present. The flip wait is what remains of the vblank (2.5-2.8 ms); keep adds 0.7-1.0 ms; the guest
  needs 0.2 ms. The plan's guess (the copy is the largest cost besides the flip wait) is confirmed:
  it is the largest cost outright.
- **59.9 presents/s, every one a surface flush** (`noted` = `flushes` = `presents`), none full-screen,
  none composed (no pointer drawn). Attract mode changes 850-1200 px per flush on average (max 99824
  of 518400), and each costs a full 1920x1080 copy. Still unmeasured: how many flushes make one
  Pinball frame. Every present blocks for a vblank, so 59.9/s is the display's rate, not Pinball's;
  two flushes per game frame would look the same.
- **Guest CPU equals guest wall time** (0.22 ms both): the guest does not wait between presents.
  `getrusage(RUSAGE_THREAD)` from libkernel works; `thread_cpu_other=0` (one presenting thread).
- **keep is bimodal across launches** (0.69 or 1.03 ms, the same within a launch); cause not measured
  (where `last_drawn` lands, cache state). It is not gated.
- **One missed vblank** in 3595 presents at 18:03 (a 17.6 ms flip).
- **fps 54 in f vs 59.9 here:** f's 54 was hand play, these are attract mode; not compared (by design).

**Built for p1 (uncommitted; the user commits):**
- Fork:
  - `native/orbis/pw_hist.{c,h}` (new, title code: the core `src/` formats nothing,
    `tests/test_native_contract.py`) and `tests/test_pw_hist.c`, in the Makefile and
    `build_native_orbis.sh`;
  - `native/orbis/pw_milestone_orbis.{c,h}`: plan `p1`, `p_script`, the per-present timings in
    `pw_ms_present`, `pw_ms_flush`, `p1_lines`; f's play loop split into `f_play` (p1 runs it after
    the line);
  - `native/orbis/wine64_main_orbis.c`: the flush sink set from ntdll's descriptor; the netlog
    datagram buffer 2100 bytes;
  - `native/orbis/orbislog/orbislog.c`: datagrams up to 2048 bytes, klog stays 512
    (`ORBISLOG_KLOG_MAX`);
  - `wine/ps5/pw_wine_sink.{c,h}`: `pw_wine_set_flush_sink`, `pw_wine_note_flush` (tested in
    `tests/test_pw_wine_sink.c`), exported by `ntdll.prx` (`build_wine_orbis.sh`);
  - `wine/patches/1080-win32u-orbis-note-each-present.patch`: `present_screen` tells ntdll each
    present's dirty area, the desktop's area and whether it composed. Numbered 1080, after every
    patch that touches `ps5drv.c` (the last is 0902): as 0490 it did not apply to a fresh series.
- Repo: `check.sh p1` (with `num`; the line is the last copy or a longer copy it begins, because
  klog keeps 512 bytes), `tests/check_p1_test.sh` + 8 fixtures, `build.sh probe-test` runs it.
- Host tests: fork `make test` exit 0; `build.sh probe-test` exit 0 (a-f, p1).

**Measurement notes for later steps:**
- "First present" is the first frame after the Wine stage begins: 1.3-1.5 s in, while PINBALL.EXE
  opens its window (it loads at 1.2 s). The segment runs from ~22 s to ~82 s.
- orbis-compat's `clock_gettime` answers every CPU-time clock id with the monotonic clock, so
  `CLOCK_THREAD_CPUTIME_ID` would have been wall time; hence `getrusage`.
- Until 2026-11-01 18:00 every netlog datagram was cut at 512 bytes (`ps5log_raw`), the f lines
  included.

**Next:**
1. The user commits, fork and repo.
2. p2 (native WoW64): first the `sigaltstack`-via-syscall-53 stage. Or p3/p4 (one package, env.txt
   toggles): T3 is written below, before p3's first run.

Phase p does not gate g unless a rule says so. The one link: g runs on the native CPU when p2
passes, else on the translator.

## Known (from the code and LOG.md; stated, not re-derived)

**The present path today** (fork `native/orbis/`):
- `pw_ms_present` (`pw_milestone_orbis.c:680`) swizzles BGRA→RGBA per pixel and integer-scales
  960x540 to 1920x1080 on the CPU, under `present_lock`.
- On every present that draws, it also copies the whole source frame into `last_drawn`
  (`pw_milestone_orbis.c:742-745`, 2 MB at 960x540), kept for the framebuffer readback.
- `pw_videoout_orbis_flip` (`pw_videoout_orbis.c:81`) submits `FLIP_VSYNC` and busy-waits on
  `sceVideoOutIsFlipPending` (up to 100 × 1 ms `nanosleep`) inside that lock. Presents are already
  vsync-locked and block the caller: `present_ms=16.6` in the f line. Two buffers.

**What the f line says about time** (LOG 2026-11-01 16:52):
- 3862 presents in 71 s = 54.4/s, an 18.4 ms frame, 16.6 ms of it inside the present. The guest
  gets ~1.8 ms per frame. The translator is not Pinball's bottleneck.
- A speed gate on guest time would test ~0.2 ms against run-to-run noise. Guest time is recorded in
  every p line and gated nowhere.
- fps (54) sits under a 60 Hz ceiling, and the GDI driver presents only on change. fps is not a CPU
  metric; p compares per-flush times, never fps.
- A "present" is a win32u surface flush, not a game frame. If Pinball's table and score panel flush
  separately, one game frame costs two copies and two vblank waits, which could explain part of the
  54/s. Unmeasured: p1 records it.
- Unblocked, Pinball can exceed 60 frames/s: on the host it ran ~63 fps in attract mode (2517
  frames in 40 s, `HANDOFF-f.md` "Host evidence"). On the Jaguar this is unmeasured; p4's gate
  relies on it.

**The Vulkan path is different** (scope of p3/p4):
- p3 and p4 change the GDI sink only. D3D9 in g presents through mesa-ps4's `wsi_orbis.c`, which
  already returns after `sceVideoOutSubmitFlip` and throttles on a flip slot
  (`wsi_orbis_wait_for_flip_slot`: proceed while `numFlipPending < count-1`, `sceKernelUsleep(500)`,
  2 s bound).
- Measured by mesa-ps4, not by us: the display accepts several pending flips, 21 in ~110 ms, and then
  the queue overflowed and presentation failed (`refs/mesa-ps4/src/vulkan/wsi/wsi_orbis.c:398`,
  `:549`). An async present needs the slot limit.
- The same file says "nanosleep does not return on this platform". Our flip loop's `nanosleep` did
  return in f. The two disagree, so new waits use `sceKernelUsleep`.

**VideoOut sizes** (milestone a, `probes/probe.c:705-718`): a 1280x720 A8R8G8B8_SRGB set registered
(`vo_720p=ok`), a 3840x2160 set was refused (`0x80290005`). Registering a smaller set is measured;
flipping one is not.

## The benchmark (every p launch)

- **Plan `pN`** (`PS4WINE_MILESTONE=pN` in env.txt) is plan `f`'s Pinball with the pad bindings off.
- **Segment:** warm-up W = 20 s from Pinball's first present, then N = 60 s in attract mode with no
  input. The same W and N every run, so runs compare like with like.
- **No input:** the title counts every pad event inside the segment; `inputs=0` is required, so a
  touched pad fails the run instead of skewing it.
- **After the segment** the line is sent. The pad bindings then switch on, and the user may play.
  Hand play goes to a `PW_MS play` record and the LOG notes, never into a comparison.
- **Run conditions**, noted in each LOG line: viewer open, no other app running, desktop 960x540.

## p1's instrumentation (stays in every later build)

Each step is re-measured on the same segment with the same fields.

Per present (= per flush), in integer µs (a precision choice):

| Metric | From | To |
|---|---|---|
| `guest` | the previous present's exit | this present's entry (translated code + Wine + the guest's own waits) |
| `copy` | swizzle + scale start (p3: its copy) | end |
| `keep` | the `last_drawn` copy's start | end (its own field, not inside `copy`) |
| `flip` | flip call entry | return (the time the caller spends there) |
| `frame` | present entry | next present entry |

- Fixed 100 µs buckets up to 100 ms plus an overflow bucket, no allocation per frame. Exact
  min/avg/max; p95 from the buckets.
- Line fields: `guest_us_min guest_us_avg guest_us_p95 guest_us_max`, the same four for `copy_us`,
  `keep_us` and `flip_us`, plus `frame_us_avg` and `presents`.
- `guest_cpu_us_avg` from `clock_gettime(CLOCK_THREAD_CPUTIME_ID)` on the presenting thread,
  `thread_cpu=ok|err:<rc>` (unmeasured on Orbis). It separates the guest's CPU time from its waits.
  As built: `getrusage(RUSAGE_THREAD)` (`pw_milestone_orbis.c:794-805`), because orbis-compat answers
  CPU-time clock ids with the monotonic clock ("Measurement notes" above).
- **Flushes:** `flush_hz` (presents per second over the segment), the dirty area per flush
  (`dirty_px_avg`, `dirty_px_max`) and `full_flushes`. `pw_ms_present` receives the whole frame and
  no rectangle, so the driver tells ntdll each present's dirty area just before it (patch 1080,
  `pw_wine_note_flush` → the title's `pw_ms_flush`). With the histograms this shows
  whether one game frame is several flushes.
- The sparse histograms go to netlog as `PW_MS hist <metric> ...` records for plots, not into the
  line.

## Sub-steps

Each step: its own `PS4WINE pN` line, a `check.sh pN` rule and `tests/check_pN_test.sh` with
`tests/fixtures/pN-*.log` before its first run, one LOG line per launch. Every line also carries
p1's fields, `build=`, `session_s` and the stage fields as in f.

| Step | What | Rule (`check.sh pN`) |
|---|---|---|
| p1 | Measure. 3 launches of one package, for the run-to-run spread | `PS4WINE p1 bench pinball cpu=translator seg_s=60 inputs=0 presents>=600 faults_unresolved=0`, every histogram field present. No performance threshold |
| p2 | Native WoW64 | `PS4WINE p2 native native_caps=7 cpu=native seg_s=60 inputs=0 faults_unresolved=0 segment=done` |
| p3 | Drop the CPU copy (**passed 18:31, vo720**) | `PS4WINE p3 bench pinball ... present_path=vo720\|vo1080 vo_register=ok vo_flip=ok seg_s=60 inputs=0 faults_unresolved=0 copy_us_avg<=T3` **and** HDMI 960,540 = 0,255,0, 240,135 = 255,128,0 |
| p4 | Non-blocking present (**passed 18:40**) | `PS4WINE p4 bench pinball ... present_mode=async buffers=3 seg_s=60 inputs=0 faults_unresolved=0 shown_hz>=59 flip_errors=0` **and** p3's HDMI pattern check |
| p5 | Orbis audio | `PS4WINE p5 audio driver=orbis open=ok seg_s=60 inputs=0 faults_unresolved=0 grains_nonzero>=G underruns=0`, the rate gate below, **and** the recording's audio peak >= D dBFS in the tail's window |

### p1: measure

- The instrumentation above, nothing else changed. The p1 line records numbers only.
- Three launches of the same package give the spread s of each metric (below), which the thresholds
  are built on.

### p2: native WoW64

- f4's readiness probe: an Orbis variant of 0883 as its own patch, not 0883/0903 widened wholesale.
- **First stage, before anything else:** does `sigaltstack` work as syscall 53 through libkernel's
  `syscall` stub? (`sigaltstack` returns -1 through libc, c and d.) Field `altstack53=ok|err:<rc>`.
- The stub is found by checking its bytes (`mov $N,%rax; mov %rcx,%r10; syscall; jb; ret`), as 0883
  does (fork `docs/native-wow64-provider.md`), not used as a fixed `getppid+10` offset (that is
  only where a measured it).
- Then 0883's checks: raw `sigaction` (416) through the stub, the frame check with a marked MXCSR,
  the aligned alternate stack. Caps 0 on any mismatch; the translator runs either way (0614).
- With `native_caps=7`, the segment runs on `cpu=native`.
- **Gate: correctness only** (`native_caps=7`, `faults_unresolved=0`, `segment=done`). `guest_us_*`
  and `guest_cpu_us_avg` are recorded against p1, not gated: with ~1.8 ms of guest time per frame,
  noise would decide any speed gate.
- caps < 7 is a FAIL that names the failing check. g and h then stay on the translator.

### p3: drop the CPU copy

- **Outcome (2026-11-01):** 960x540 is refused by VideoOut; `vo720` passed, `vo1080` failed on a
  read-back fault (see "Resume here"). The text below is the plan as written.
- **First try** 960x540 A8R8G8B8_SRGB linear VideoOut buffers. The driver's BGRA is that format's
  memory order, so a row `memcpy` replaces the swizzle and the scale.
- Whether VideoOut scales a smaller buffer to 1080p is unmeasured (see "VideoOut sizes").
- **The pitch is a parameter:** 960, with 1024 as the fallback if 960 is refused (then the copy is
  row by row).
- **The keep copy:** p3 states whether vo540 keeps the `last_drawn` copy (`keep_us`) or moves it,
  for example by taking the readback from the 960x540 scan-out buffer itself.
- **Test pattern, same launch, before Wine:** the title flips a 960x540 version of d1's pattern for
  3 s, recorded over HDMI. The green centre is at 480,270 and a 32x32 orange square is centred on
  120,67, so a 2× scale puts them on HDMI 960,540 and 240,135. A buffer shown unscaled in the
  top-left corner fails the check, as it should. Fields `vo_register`, `vo_flip`, then the segment.
- **GPU (RADV) only if VideoOut cannot scale.** It loads a 1 GiB arena into a plan that is RADV-free
  today, so that path gets its own decision, not a p3 retry.

### p4: non-blocking present

- 3 buffers. Submit `FLIP_VSYNC` and return.
- Wait only for a flip slot, when `numFlipPending >= count-1`: the WSI's rule. The wait happens
  outside `present_lock`, with `sceKernelUsleep` and a 2 s bound.
- **Path:** p3's result, vo540 if p3 passed, else today's scale path, fixed before p4's run.
- **Gate:** `shown_hz>=59` (flips completed per second over the segment, from the flip status) and
  `flip_errors=0`. The visible problem today is missed vblanks: 54/s, not 60.
- `flip_us_*` and `slot_waits` are recorded, not gated. Once the present returns before vblank,
  Pinball can outrun 60/s and the caller waits for a slot instead, and that wait lands in `flip_us`.
- Same HDMI pattern check as p3.

### p5: Orbis audio on sceAudioOut

1. **Explain milestone a's `sceAudioOutOpen` = 0x809b0001 first.**
   - The probe (`probes/probe.c:727`) called `sceAudioOutOpen(initial user 481013703, MAIN, 0, 256,
     48000, S16 stereo)` (`logs/20261030-001125-a.log`). Its klog at line 602 has
     `[AudioOut] Error:sceMbusAddHandleByUserId 0x20000007`: the system side refusing that user id.
   - OpenOrbis's sample (`refs/OpenOrbis-PS4-Toolchain/samples/audio-wav/audio-wav/main.cpp:24,38`)
     and nx-on-orbis's eden patch 0002 (`UserIdSystem = 0xFF`, the sequence ARCHITECTURE §4.11
     calls clean) open with the SYSTEM user 0xFF.
   - orbis-porting-kit `services/audio/orbis_audio.h:31,115` records 0x809b0001 for a real user id
     instead of SYSTEM.
   - Hypothesis: the user id. The p5 launch's first stage opens with 0xFF (`open=ok user=system`);
     the initial user is tried again only if 0xFF fails.
2. **Facts from `orbis_audio.h`** (facts, no code taken):
   - 48000 Hz only; the grain is a multiple of 256, from 256 to 2048;
   - `sceAudioOutOutput` blocks and is the clock: it runs on its own thread, never a render thread;
   - `sceAudioOutSetVolume` after Open (the port can open silent);
   - open once and never close (close and reopen is disputed: PORT_FULL after eight cycles);
   - one audio output stream per process (`orbis_audio.h:35`): `wineorbis` mixes every Wine stream
     into the one port it opens once.
3. **The title's `native/orbis/pw_audio_orbis.c`**, from `native/pw_audio_ps5.c` with the same
   256-frame grain contract. Counters `grains`, `grains_nonzero` and `underruns` (a grain sent as
   silence while a stream is open and the ring is empty), counted from the first grain to the line.
4. **`wine/wineps5` ported and renamed `wineorbis`** (ARCHITECTURE §4.11), built by
   `build_wine_orbis.sh`. Patch 0120's default driver is `orbis` on Orbis (today mmdevapi logs "No
   driver from ps5 could be initialized").
5. **Host first:** the fork's driver fixture plays Pinball's scripted tail into a host sink (WAV)
   and counts nonzero grains. That count sets G.
6. **The launch:** the segment as in p1, then a scripted tail of title-injected keys (F2 new game,
   space held 1 s and released, Z and `/` flippers) so Pinball plays its WAV effects.
7. **HDMI audio:** `view.sh --record X.mkv` records video only (mpv runs `--no-audio`; the sound
   goes through `pw-loopback`). Add an `X.wav` sidecar recorded from the stick's PipeWire source
   (`pw-record`: a second reader of the audio source, not of the V4L2 node). `check.sh p5` reads its
   peak with ffmpeg `volumedetect`. HDMI audio does reach the laptop: the user heard the home screen
   (LOG 2026-11-01 16:44).
8. **One package, two launches:** `PS4WINE_AUDIO=off|on` in env.txt. The off launch is the baseline
   for the rate gate, on the same present path.
9. **Gate:** `open=ok`, `grains_nonzero>=G`, `underruns=0`, the rate gate (thresholds), the HDMI
   peak. Guest time is recorded, not gated: WaveMix mixes in translated guest code, so audio may
   cost more than ~0.2 ms and still play fine.
10. **MIDI music:** `midi=untested`. It needs a synth that Orbis Wine lacks.

## Thresholds

Written here before each step's first run, from measured numbers, and never moved after seeing that
step's data. Spread s = (max − min) / mean of a metric over p1's 3 launches.

| Step | Threshold | Rule | Value |
|---|---|---|---|
| p2 | none | correctness only | – |
| p3 | T3 for `copy_us_avg` | p1's copy avg × (1 − max(0.10, 3s)). The copy is expected to be the largest cost in the present besides the flip wait; p1 confirms or refutes that before T3 is written. p1 (2026-11-01): mean 12941 µs, s = 0.05 %, so the 10 % floor applies; confirmed, the copy is the largest cost | **11647 µs** (written 2026-11-01 18:06, before any p3 run) |
| p4 | `shown_hz` | >= 59, fixed now from the 60 Hz display (a: 60.5 Hz, d1: 59.9 Hz), not from data | 59 |
| p5 | rate gate | p4 passed: `shown_hz>=59`. p4 failed: `flush_hz` >= the audio-off launch's `flush_hz` − 3 × p1's `flush_hz` spread (in Hz; p1 runs sync and has no `shown_hz`). The branch is fixed when p4's verdict is in. p1's `flush_hz` spread: 0.033 Hz, so 3× = 0.10 Hz | branch after p4; margin 0.10 Hz |
| p5 | G for `grains_nonzero` | the host run of the same tail | after the host run |
| p5 | D (dBFS) for the HDMI peak | above the level of a recording with the PS4 silent | after that recording |

## Batching

- **p1:** one package, 3 launches.
- **p3 and p4:** one package with env.txt toggles: `PS4WINE_MILESTONE=p3|p4`,
  `PS4WINE_PRESENT_PATH=scale|vo540`, `PS4WINE_PRESENT_MODE=sync|async`. Several variants per
  install, each launch its own LOG line. A p1 re-measure (scale + sync) can run from the same
  package.
- **p2:** its own package (patch work).
- **p5:** one package, `PS4WINE_AUDIO=off|on`, two launches, two lines.

## Host first, tests

- `tests/check_pN_test.sh` with `tests/fixtures/pN-*.log` per step: a pass, input during the
  segment, a missing histogram field, a threshold miss, stage records only (NOLOG naming the
  stages).
- p3/p4: HDMI pixels from generated 1920x1080 dumps, as `check_f_test.sh` makes them (scaled
  pattern passes, unscaled top-left pattern and swapped red/blue fail).
- p5: generated WAVs (a sine passes, silence fails).
- `build.sh probe-test` runs them; `check.sh`'s STAGES branch includes `p[1-5]`.
- The histogram and percentile code is host-tested in the fork.

## Not tested / unmeasured (say so in the LOG lines)

- VideoOut scaling a 960x540 buffer, and flipping any non-1080p set;
- A8R8G8B8's colour order on HDMI;
- a 960-pixel pitch;
- `CLOCK_THREAD_CPUTIME_ID` on Orbis;
- syscall 53 (`sigaltstack`) through libkernel's stub;
- attract mode's run-to-run stability (p1 measures it);
- how many flushes one Pinball frame takes, and their dirty area (p1 records it);
- whether Pinball outruns 60/s on the Jaguar once the present is async;
- MIDI.

## Milestone g after p

- The rewritten g (MILESTONES): Bloodlines from `games/bloodlines-up`, `Vampire.exe -game
  Unofficial_Patch`, rule `PS4WINE g vtmb batch=1 crossings_per_frame<=2000 fps_avg>=20
  session_s>=300 faults_unresolved=0`; "gameplay reached, batching on, 300 s".
- Its unmeasured risks, moved from h: VirtualAlloc at fixed addresses, the large-address (2 GB RAM)
  fix, `Vampire.exe` relocated off the eboot's 0x400000.
- What g takes from p:
  - p2 decides the CPU: native when p2's correctness fields pass (`native_caps=7`,
    `faults_unresolved=0`, segment done); speed plays no part.
  - p5 gives sound (Miles goes through Wine's audio); g's rule does not gate it.
  - p3/p4 are GDI-sink only; g's D3D9 presents through `wsi_orbis.c`.

## Iteration loop (as in f)

```
scripts/ps4/build.sh wine --skip-host        # Orbis PRXs
scripts/ps4/runtime.sh --prx-only            # PRXs + *.bind.txt to /data
scripts/ps4/build.sh title                   # when native/orbis changed
cp dist/ps4-wine-<id>.pkg dist/ps4-wine-<id>-<tag>.pkg && scripts/ps4/deploy.sh dist/ps4-wine-<id>-<tag>.pkg
scripts/ps4/logs.sh --label pN --expect 'PS4WINE pN ' --timeout 600 &    # before the user launches
scripts/ps4/view.sh --sink ... --record logs/<ts>-pN.mkv &               # the user's screen + HDMI evidence
scripts/ps4/check.sh pN                      # plus the HDMI checks for p3/p4/p5
```

Choose the plan and variants in `/data/ps4-wine/env.txt` (`PS4WINE_MILESTONE=pN`, the toggles
above). Give each package build its own file name. Close the running title before a reinstall
(CE-33237-8).

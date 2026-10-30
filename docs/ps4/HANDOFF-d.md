# Hand-off: milestone d (winemine with the DS4)

Written 2026-10-30. Read `CLAUDE.md`, `HANDOFF-c.md` (how c was reached), then this. The plan
splits d into five sub-steps, riskiest first. Each has its own `PS4WINE dN` line and its own
`check.sh dN` rule. The milestone's own rule (`check.sh d`) is the last of them. **d1 passed on
its first launch (2026-10-30 14:45); d2 and d3 passed together on the fifth d2 launch
(15:29); d4 passed on its second launch (15:52); d5, milestone d itself, passed by its rule
on its third launch (16:05) with input latency the user found far too high, and again at 16:10
after the present fix, "super smooth" (8 ms input to frame on average). Milestone d is done; e is
next.**

## Cleanup after c (done 2026-10-30, fork branch `orbis`, uncommitted)

- **Patches 1030 and 1040 dropped.** They were silent in runs 13–15. Upstream comes back:
  - `fatal_error` on a server-dir identity mismatch (the stat family makes it pass);
  - plain `release_object` on the startup mappings.
- **Patches 1050 and 1060 dropped.** They held only handshake and request traces. The
  `WINE_ORBIS_POLL` knob went with them: kqueue never misbehaved.
- **Patch 1070 reduced to its `init_thread` hunk.** It was rebased on upstream and renamed
  `1070-server-orbis-blocking-reply-fd-when-o-nonblock-is-refused.patch`. With kernel pipes (the
  Orbis default) the fallback is not taken; it matters only with `WINE_ORBIS_KERNEL_PIPE=0`.
  The client-socket and wake-pipe print hunks went (upstream ignores those returns).
- **Title probes trimmed.** `probe_pipe` and `probe_fds` are gone; their answers are in LOG runs 1
  and 10. `probe_module` stays as the harness for d1.
- **Stat dump removed.** The one raw `sceKernelStat` hex dump in the compat `stat()` is gone (LOG
  run 7 has the bytes). The open+`_fstat` dev/ino fallback stays.
- **Still to confirm:** that the c path still passes on the console. That rides on the d1 launch:
  the title runs `hello.exe` after the d1 tests, and the d1 line carries `hello=ok`.

## Console facts carried from c (unresolved)

- **No descriptor duplication.** `dup` is EPERM and `F_DUPFD` EINVAL on every descriptor kind.
  The reopen-by-path wrap covers files only. The server's `dup_fd_object` on sockets, pipes and
  shared memory needs a real answer: share the descriptor with a refcount on Orbis.
- **No `O_NONBLOCK` on AF_UNIX sockets** (`F_SETFL` and `FIONBIO` both EACCES). The accepted client
  socket stays blocking (POLLIN only, fine). Winsock (`server/sock.c`) will need `MSG_DONTWAIT`
  per call. The compat `fcntl` wrap logs that refusal once per launch.
- **`sigaltstack` returns -1.** Wine's fault handlers have no alternate stack. Nothing has faulted
  under Wine yet.
- **Untested:** `WINE_PS5_SERVER_DIRECT=1` and the shared mutex/sync backends.
- **ENOSYS stubs still linked:** `times()`, `setsid()`, `setpgid()` (results unread, or never
  reached).

## Why binding comes first

- **win32u has never been a PRX on Orbis.** `build_wine_orbis.sh` links `win32u.shared.elf`, but
  `create-fself` refuses it: `missing library for symbol (RtlSetLastWin32Error)`.
- **78 imports are unbound.** `report.json` gives win32u 126 imports, 78 of them unbound (Nt*/Rtl*,
  `wine_server_*`, `__wine_dbg_*`, `ntdll_*`, `NtCurrentTeb`, `KeUserModeCallback`), with no data
  imports.
- **win32u has its own libc copies.** Its static link takes musl's own `dlsym` and `malloc`. Patch
  0400's `dlsym(RTLD_DEFAULT, "pw_wine_present")` would fail, and win32u's heap would not be
  Wine's.
- **No precedent.** Nothing has measured an app PRX importing from another app PRX on the PS4.
  ntdll and wineserver talk only through descriptor look-ups (`pw_wine_dl`, PRXDESC1).
- **What the PS5 does.** It links win32u against `ntdll.shared.elf`, and the firmware binds
  function imports. Data imports fault there (FW 12.02).

## The sub-steps

All pixel checks use the framebuffer readback from b (`/data/ps4-wine/shot.raw`, R,G,B,A,
1920×1080; `fbshot.sh`; `check.sh --fb`), not the capture stick. Expected pixel values are fixed
here before the console run, from host reference frames, and never adjusted afterwards. One launch
adds one LOG.md line, which names every `PS4WINE` line the launch emitted.

### d1: cross-PRX binding, plus VideoOut, the c regression and a DS4 probe in the same launch

**PASSED 2026-10-30 14:45 on the first launch** (LOG.md, `logs/20261030-144218-d1.log`):
`bind=import`, every stage ended, `hello=ok`, framebuffer pixels exact.
- **Decision: method A** (loader imports) for win32u and the later PRXs. Method B stays built and
  tested as the fallback.
- **Load order is the caller's job:** the loader does not load a NEEDED app module by itself
  (`early_autoload=0`).
- **Data imports bind on the PS4** (unlike the PS5's FW 12.02); the build still refuses them for
  win32u.
- **Open for d2: win32u's `dlsym` slot was `other`, not equal to `sceKernelDlsym(ntdll, "dlsym")`.**
  libkernel exports `dlsym`, `dlopen` and `dlclose` too, so either the slot or the look-up took
  libkernel's. Log the slot value with `module+offset` and compare it with ntdll's descriptor entry
  for `dlsym` before patch 0400's `dlsym(RTLD_DEFAULT, "pw_wine_present")` is relied on.

**How a PRX imports from another app PRX** (measured on the host, `create-fself`):
- create-fself opens each NEEDED soname as a file in `-library-path` and reads its ELF symbols.
- It names the import module and library after the NEEDED soname less `.so`. It names an
  exporter's own module and library after `-libname`, or the input file stem without it. Before
  d1, ntdll called itself `ntdll.shared`, so nothing could import from `ntdll`.
- So every Orbis PRX is now linked `-soname NAME.so` and converted with `-libname=NAME`
  (`build_wine_orbis.sh`, `build_native_orbis.sh`). The importer's NEEDED is then `ntdll.prx`,
  and module and library are `ntdll` on both sides.

**Two-PRX test** (fork `native/orbis/pw_bind_*.c`, built by `build_native_orbis.sh`):
- `pw_bind_lib.prx` exports `pw_bind_add`, `pw_bind_name`, `pw_bind_calls` and the data object
  `pw_bind_counter`.
- **Method A, loader imports.** `pw_bind_use.prx` and `pw_bind_early.prx` (one source) import the
  two functions.
  - They are linked against a stub from `tools/orbis_import_stub.py`.
  - `tools/orbis_bind_table.py` writes their slot tables (`*.bind.txt`: offset, kind, exporter,
    symbol).
- **Data import.** `pw_bind_data.prx` takes `pw_bind_counter` through a `GLOB_DAT` GOT slot
  (`-fPIC`; the build refuses a copy relocation).
- **Method B, thunk table: the fallback that needs no loader support.**
  - `tools/gen_prx_imports.py` gives each name a `jmp *slot(%rip)` thunk.
  - An exported `pw_prx_bind_imports(resolver)` fills the slots.
  - `pw_bind_thunk.prx` has no loader import of the lib at all, and the build checks that.
- **Host tests** in `make test`: `test_orbis_prx_imports.py` and `test_gen_prx_imports.py`.

**At scale: win32u.prx** (built for the first time; it was "NOT BUILT" since c):
- **An explicit import set.** Linking against ntdll's whole dynamic table also bound win32u's
  static musl to ntdll's `__musl_current_locale` (a `TPOFF64` TLS import) and `__tls_get_addr`.
  So `orbis_import_stub.py` gives win32u only:
  - what a first link leaves unresolved and no SDK stub provides (Wine's 78 symbols, the
    exporter's `__wrap_*` hooks);
  - plus the `dl*` and malloc families on purpose.
  Data and TLS symbols are refused. Result: 89 slots from ntdll, all `JUMP_SLOT`, no data or TLS
  imports, 0 unbound in `report.json`.
- **The wraps.** win32u is linked with ntdll's `exit`/`write`/`dup`/`fcntl`/`pipe` wraps, so its
  `__wrap_*` calls are ntdll's (a title may not exit, and fd 2 goes to the title's sink).
- **The slot table.** The build writes `win32u.bind.txt`. The title loads ntdll.prx and
  win32u.prx, then compares each slot with `sceKernelDlsym(ntdll, name)`:
  - `bound`: equal;
  - `zero`;
  - `lazy`: still a PLT address inside win32u;
  - `other`;
  - `nosym`: the look-up fails.
  That gives `w32u_bound=N/89` and catches wrong NIDs: the PS5's runs 8–10 had every import 0.

**Title side, same launch:**
- `native/orbis/pw_videoout_orbis.c`: two linear 1920×1080 buffers in Garlic direct memory,
  `A8B8G8R8_SRGB` (0x80002200, as `wsi_orbis.c`). The CPU draws b's test pattern for 120 flips,
  and the flipped buffer goes to `shot.raw` (tmp, fsync, rename as `probes/triangle.c`).
- `native/orbis/pw_pad_orbis.c`: `sceUserServiceGetInitialUser`, `scePadInit/Open/ReadState`.
  The pad data size and offsets are logged, plus whether cross was pressed in the first 10 s (the
  user presses it).
- Then `hello.exe` as in c.

**Stages and the progress file.** The d1 launch is a fixed sequence of stages. A crash or hang in
one stage must not lose the results of the others.

- **Order:**

  | # | Stage | Time limit |
  |---|---|---|
  | 1 | `bind_early` (an importer loaded before its exporter) | 10 s |
  | 2 | `bind_lib` | 10 s |
  | 3 | `bind_import` (slots before and after the first call) | 10 s |
  | 4 | `bind_thunk` | 10 s |
  | 5 | `bind_data` | 10 s |
  | 6 | `w32u_bind` | 20 s |
  | 7 | `videoout` | 15 s |
  | 8 | `pad` (waits up to 10 s for cross) | 15 s |
  | 9 | `hello` | 180 s, the c watchdog from this stage's start |

  The bind tests come first. "Before the exporter" can only be tested before anything loads
  `pw_bind_lib`, so `bind_early` is first; it never calls through its slots.
  - `bind_import` does not call when a slot is 0. It reports `import_slots=zero` instead of
    faulting.
  - The data import, which faults on the PS5, runs after every function-import stage.
  - win32u's 89 slots run after the small test.
  - Each stage loads `pw_bind_lib` itself if needed, because a resumed launch is a new process.
- **Progress file** `/data/ps4-wine/d1/progress.txt`, separate from the a-probe's. Every line is
  written and `fsync`ed before the next step:
  - `B:<stage>` before the stage;
  - `R:<stage> key=value ...` with its result fields;
  - `E:<stage>` after it.
  Each `R:` line also goes out at once on netlog and klog as `PW_D1 stage=<stage> ...`. That
  prefix never matches `check.sh`'s `PS4WINE d1 ` grep, so `logs.sh` has every finished stage
  even if the launch dies next.
- **Fault inside a stage.** Stages 1–8 are title code and loader calls, run under the title's
  fault handler.
  - A fault there writes `F:<stage> sig= addr= rip=<module+offset>`, records the stage's fields
    as `fault`, and `siglongjmp`s back to the runner, which goes on with the next stage.
  - This works only with stack left: there is no `sigaltstack`, so a stack overflow is not
    caught.
  - A second fault while recovering stops the recovery. So does a kernel kill no handler sees
    (SIGSYS, CE-34878-0).
  - In both cases the `B:` without an `E:` is the record.
- **Hang.** A watchdog thread checks the current stage's deadline.
  - On overrun it writes `H:<stage>`, emits the d1 line with what is known (`stopped=<stage>:hang`),
    and the title idles. A stuck thread cannot be ended on this kernel, and `exit` is
    CE-34878-0.
  - `hello` keeps c's watchdog and fault paths. Wine installs its own handlers, so that stage
    does not recover.
- **Relaunch resumes.**
  - At start the runner reads the progress file.
  - A stage with `E:` is not run again; its `R:` fields are reused.
  - A stage with `B:` and no `E:` is recorded as `crash` (or `hang` after an `H:`) and skipped.
  - The rest run.
  - The line then carries `launches=N` and `resumed=<stages taken from the file>`.
- **New cycle.** Once the d1 line has gone out with every stage ended, crashed or skipped, the file
  is renamed to `progress.last`. It stays readable over FTP, and the next launch starts a fresh
  cycle. Deleting `progress.txt` over FTP also forces one.
- **The fork's own code.** The runner is new code in `native/orbis/pw_stage_orbis.{c,h}`, written
  for the fork. It takes the a-probe's idea and console facts (fsync'd results on `/data` survive
  a crash), not its code: `probes/probe.c` is GPL-3.0 from nx-on-orbis.
- **Host test.** File access goes through a small ops table, so the fork can host-test it
  (`tests/test_pw_stage_orbis.c` in `make test`): fresh cycle, resume after a `B:` without `E:`,
  `H:` and `F:` records, a torn last line, rename on completion.
- **The c line still comes out.** The `hello` stage emits c's `PS4WINE c` line as before. The d1
  line follows it; at a stop it comes alone.

**Line** (once per launch, at the end or at a stop):
```
PS4WINE d1 bind=import|thunk|none lib= import= import_slots=bound|lazy|zero|mixed order_needed=0|1 data= thunk= w32u_load= w32u_bound=N/89 w32u_zero=N videoout= fb= flip_hz= pad=ok|none pad_cross=0|1 pad_bytes=N hello=ok|<c exit> build= stages=<ended>/9 stopped=-|<stage>:crash|hang,... launches=N resumed=-|<stage>,... session_s=N
```
Each stage field is its result, or `fault` (recovered in this launch), `crash` (lost in an
earlier launch), `hang`, or `-` (not reached). Every stage's full fields are in its
`PW_D1 stage=` record, and its sub-steps in `PW_D1 step` records (netlog only).

**Rule:**
- `bind` is `import` or `thunk`;
- `videoout=ok`, `fb=ok`, `hello=ok`;
- `--fb` pixels `960,540 = 0,255,0` and `240,135 = 255,128,0`.
- Pad fields are recorded, not gated. So are `data`, `order_needed`, `stopped` and `resumed`.
- **Several launches.** The gate can pass on a resumed launch. Each launch still gets its own
  LOG.md line, and a resumed one says which stages came from the file and from which earlier
  launch.

**Decision:**
- Keep method A if `w32u_bound=89/89` and the import works.
- Otherwise use method B for win32u (and later winevulkan).
- If `import` fails because the loader cannot find `pw_bind_lib.prx` (load error, `order_needed=1`)
  while the lib is loaded, the next hypothesis is the loader's search path. Put the PRXs in the
  package's `sce_module/` too and launch again: one more launch, no code change.
- Last resort: win32u linked statically into ntdll.prx (not built).

### d2 + d3: win32u, GDI and fonts from one gdi64.exe launch

**PASSED 2026-10-30 15:29** (d2 and d3 in one launch, the fifth; LOG.md has all five):
`PS4WINE d2 gdi win32u=ok driver=ps5 pixel=ff8000 exit=0 ... fb=ok w32u_bound=95/95` with the
framebuffer pixels, and `PS4WINE d3 fonts n=9 tahoma=1 text_px=419 exit=0 ... tahoma_mmap=ok:00010000`.

**What the five launches taught:**
1. The window reaches the TV through the present sink (seen by the user).
2. The user driver presents on changes only (2 frames for a window shown 2 s), so the readback
   keeps the last drawn frame and saves it at exit.
3. The title's own `readdir` works, but `NtQueryDirectoryFile` was STATUS_ACCESS_DENIED.
4. Cause: `realpath()` fails for every path with `libc.a` (musl's open + `readlink` of
   `/proc/self/fd/N`, and `readlink` is an ENOSYS stub). The in-process server therefore kept no
   `unix_name` for any file, and patch 0140's enter-by-name had no name to use. The fix is a
   lexical `realpath` in the cwd emulation on Orbis (`PW_CWD_LEXICAL_REALPATH`, host-tested).
5. Every module that opens files by Wine's `dosdevices/c:` names needs its own copy of the cwd
   emulation (the `c:` link is virtual): libfreetype (its `fopen`) and win32u (its `open`/`mmap`
   of font files), as wineserver already has. `-u opendir` keeps libc.a's `opendir`: the
   emulation's `__real_opendir` alone made ld.lld take libSceLibcInternal's.
6. A private read-only `mmap` of a file on `/data` works.

**Open:** the `GDI64` stdout line did not arrive over netlog in launches 4 and 5. The plan's
records carry its fields, but STDOUT forwarding under load is lossy; look at it before d4 relies
on stdout.

**The `dlsym` slot from d1, settled on the host.**
- create-fself puts libkernel first among an importer's NEEDED libraries. It gives each import to
  the first library that exports its name.
- libkernel exports `dlopen`, `dlsym`, `dlclose` and `dlerror`, so win32u's `dlsym` became a
  libkernel import: 88 entries in the OELF's ntdll library for 89 in the ELF.
- **Fix:**
  - win32u is linked `--wrap=dlopen,dlsym,dlclose,dlerror,dladdr`, and ntdll exports the
    `__wrap_*` forwarders (`wine/orbis/pw_wine_dl_orbis.c`);
  - `orbis_import_stub.py` refuses a name an SDK stub the importer NEEDs also exports;
  - `orbis_prx_report.py` compares each OELF's per-library import counts (`sce_imports`) with the
    ELF's and fails on a difference. It flags the d1 build and passes the new one: win32u 94/94 from
    ntdll, `__wrap_dlsym` among them.

**FreeType.**
- The PS5's pin (2.13.3, sha256, the same units and 46 exports), compiled by orbis-clang in
  `build_wine_orbis.sh`.
- Configure takes it (`SONAME_LIBFREETYPE "libfreetype.so"`; the build fails otherwise).
- `libfreetype.prx` is 1.4 MB and imports 10 names from ntdll (the malloc family, the exit and
  stdio wraps).
- **Fonts:** Wine's 13 `.ttf` go into the prefix's `drive_c/windows/Fonts` only
  (`prefix.sh --extras`, which also adds `gdi64.exe` and checks `MenuHeight`). The runtime gets
  none.

**The title** (`native/orbis/pw_milestone_orbis.c`, replacing `pw_d1_orbis.c`).
- **Plans.** `PS4WINE_MILESTONE=d1|d2` in `env.txt` picks one, default d2. Progress files are
  `/data/ps4-wine/<plan>/progress.txt`; records are `PW_MS stage=` and `PW_MS step`.
- **The d2 stages:**

  | Stage | Does |
  |---|---|
  | `w32u_bind` | win32u's slots, the `__wrap_dlsym` slot by name (`w32u_dlsym`); an `other` slot is logged with `module+offset` |
  | `ft_bind` | libfreetype's slots and `FT_Init_FreeType` by look-up. FreeType is not called before ntdll's start, because its malloc is ntdll's heap |
  | `display` | VideoOut open, one black flip |
  | `gdi` | `C:\gdi64.exe` |

- **The present sink.** ntdll's `pw_wine_set_present_sink` hands the user driver's BGRA frames to
  the title. The title scales them by an integer factor, centres them (800×600 lands at 560,240),
  swaps them to R,G,B,A and flips. The frame one second after the first non-black one is the
  framebuffer readback.
- **Logging.** `WINEDEBUG` gains `warn+ps5drv`: patch 0400 warns "no pw_wine_present" when the sink
  look-up fails.

**gdi64.exe** (`tests/wine_gdi64.c`, host test `tests/test_wine_gdi64.py`). It prints:
```
GDI64 screen=WxH pixel=RRGGBB fonts=N tahoma=0|1 text_px=N window=ok|<call>:<error>
```
- `pixel` is an orange fill of a 64×64 DIB section, read back with `GetPixel`.
- `fonts` counts `EnumFontFamiliesExW(DEFAULT_CHARSET)` callbacks, one per family and charset.
- `text_px` counts the ink of "Wg" in 32 px non-antialiased Tahoma.
- `window` is an orange 400×300 `WS_POPUP` at 200,150 with a green 200×150 rectangle at 100,75,
  shown for 2 s.
- On the host Wine (headless, font-less): `screen=1024x768 pixel=ff8000 fonts=0 tahoma=0
  text_px=0 window=create:1400`. There is no display driver there.

**Lines** (one launch gives both; check each with `check.sh d2|d3 --log <the same log>`):
```
PS4WINE d2 gdi win32u=ok|fail driver=ps5|<screen> pixel= exit= screen= window= frames= drawn= frame= fb= server= display= w32u_bound= w32u_dlsym= w32u_first= build= stages= ...
PS4WINE d3 fonts n=<families> tahoma= text_px= exit= ft_bound= ft_first= ft_init_sym= build= stages= ...
```

**Rules**, fixed before the first launch:
- **d2:** `win32u=ok`, `pixel=ff8000` and `exit=0`, plus `--fb` pixels from the window's geometry:
  960,540 = 0,255,0 (the green rectangle) and 780,410 = 255,128,0 (the orange window).
- **d3:** `tahoma=1`, `text_px>=50` and `exit=0`, with `n>=1`. **Changed before any d3 run:** the
  planned `n>=13` was a guess the host could not confirm (its Wine has no FreeType), and the count
  is per family and charset, so `n` is recorded. 50 ink pixels is far below "Wg" at 32 px
  (a W alone is about 25×23 px with 3 px strokes).

**Not host-tested:** the user driver and the present sink (there is no host build with
`WINE_PS5_USER_DRIVER` yet; that comes with d4's reference frames), FreeType and the fonts.

### d4: winemine on screen, scripted click, framebuffer pixels

**PASSED 2026-10-30 15:52** (second d4 launch): `PS4WINE d4 winemine frames=15
board_opened=1 refused=0 fb=ok ...` with the framebuffer pixels.

**The host reference** (`tools/test_wine_ps5_driver.sh`, new in the fork).
- **The host Wine with the driver.** `.deps/wine-host-drv/build` is a copy of the host build tree
  with only win32u rebuilt `-DWINE_PS5_USER_DRIVER`. The headless host Wine has no Vulkan, and
  `vulkan.c` calls `ps5drv_vulkan_cursor`, which `ps5drv.c` defines only with `SONAME_LIBVULKAN`,
  so the copy links a one-line stub (`.deps/wine-host-drv/ps5drv_vulkan_stub.c`, host-only).
- **The prefix.** The script makes it with the plain host Wine: under the driver build, wineboot's
  `rundll32 InstallHinfSection` never returns.
- **Fixture fixes** (`tests/wine_ps5_driver_sink.c`):
  - motion is relative since patch 0670, so a point is reached as a move to the corner
    (−100000,−100000, clipped by the server) plus a move by its coordinates;
  - the frame that makes scripted input due wakes the driver's pipe, because `ProcessEvents` drains
    it and waits.
- **Result:** winemine sits at 0,0 of the 800×600 desktop, its 9×9 board's 16 px cells starting at
  8,81. A click at 80,153 opens the middle cell: its pixel 74,150 goes 0,128,0 → 0,0,0. The smiley
  is yellow at 80,58.

**The console** (plan `d4`, the title's default):
- `display`, then `winemine` (`C:\windows\system32\winemine.exe`).
- A script thread waits for the first drawn frame plus 3 s, posts the host's click through ntdll's
  `pw_wine_post_input`, and sets `board_opened` from the probe pixel's change. A whole-frame change
  would count the pointer's own motion.
- winemine does not exit, so the thread ends the Wine stage itself: the last drawn frame is saved
  and the line is emitted.

**Rule:** `frames>=2 board_opened=1 refused=0 fb=ok`, plus `--fb` 640,298 = 255,255,0 and
634,390 = 0,0,0.
- **Changed before the first d4 run:** the planned `frames>=600` assumed continuous frames, but
  the driver presents on changes only (d2).

**Launches:**
1. **First:** the layout matched (probe 0,128,0 at the predicted place, with fonts on the console),
   but the click never arrived.
   - Cause: `server/queue.c` `set_queue_fd` `dup()`s the driver's input pipe. `dup` is refused on
     the console, and the reopen-by-path fallback has no path for a pipe.
   - Fix: `__wrap_dup` duplicates any descriptor by passing it to the process with SCM_RIGHTS
     (`wine/orbis/pw_wine_dup_orbis.c`, host-tested). This also answers c's open `dup_fd_object`
     question; reopen-by-path stays as the last resort.
2. **Second:** pass.

**Open:** the last frame's smiley is winemine's pressed face, not the smile (no mine shown).

### d5: the DS4 drives the pointer, which is milestone d itself

**PASSED BY ITS RULE 2026-10-30 16:05** (third d launch): `PS4WINE d winemine frames=693
inputs=156 refused=0 board_opened=1 fb=ok ...` with d4's framebuffer pixels. The user played for
the full 150 s, and the end frame shows a large opened area.

**Not good enough to play.** The user's words: "it moves but VERRYYY delayed ... very slow input
latency". Measured: about 113 pad reads/s, 156 events in 150 s, about 4.6 presents/s. Where the
delay sits is not measured yet.

**Plan `d`** (the title's default):
- d4's click first, which gives `board_opened` and the readback kept right after it.
- Then the pad loop on the same thread, an 8 ms poll:
  - the left stick through `pw_wine_pointer_step` (`native/pw_wine_display.c`: dead zone 20,
    squared curve, at most 600 px/s), as relative `MOUSE_MOVE`s;
  - cross is the left button, circle the right;
  - OPTIONS ends the session, and so do 150 s (the Wine stage's watchdog is 180 s).
- A record each second (`PW_MS step d play`), so that a session closed from the PS menu still
  leaves its numbers. The first launch was closed that way and lost them.
- The last frame is kept as `shot-end.raw` (`fbshot.sh --remote /data/ps4-wine/shot-end.raw`).

**Fixed 16:10** (PASS again: `frames=2257 inputs=2073 refused=0 board_opened=1 fb=ok lat_avg_ms=8
lat_max_ms=510 present_ms=15.0`; the user: "super smooth").
- The lag was the title's own present: it cleared the whole 1080p buffer and copied 8 MB for
  every frame on the Jaguar. Now the border is cleared once per buffer and frame size, and the
  800×600 source frame is kept; the readback is built from it when saved.
- The line and the per-second records carry `lat_avg_ms` and `lat_max_ms` (the first pad event
  not yet shown, to the next present) and `present_ms`.

**Open:**
- One 510 ms latency spike in 150 s, cause unknown.
- The first seconds after the scripted click ignored the stick: `d4_click` settled 2 s and wrote
  the 8 MB readback on the play thread. Now it saves on its own thread and the pad loop starts at
  once (built, not yet run).
- OPTIONS ending a session is untested; both sessions ended by time.

## Tooling the sub-steps need

**Done for d1:**
- **`check.sh`:** `d1`–`d5` as ids (d2–d5 exit 2 until their rules exist), an `in` op, and d1's
  `--fb` pixels. With no d1 line, NOLOG or CRASH lists the `PW_D1 stage=` records that arrived.
- **`tests/check_d_test.sh`** in `build.sh probe-test`, with seven synthetic
  `tests/fixtures/d1-*.log`:
  - pass;
  - a recovered `bind_data` fault that still passes;
  - a resumed launch (`launches=2`) that passes;
  - a `videoout` hang, which fails on `fb`;
  - no binding method;
  - stage records only (NOLOG);
  - a crash.
  The pixel cases are checked on generated RGBA and BGRA dumps.
- **`build_native_orbis.sh`** links `-lSceVideoOut -lScePad` and builds the five bind PRXs and
  their slot tables.
- **`runtime.sh`** stages the bind PRXs, the `*.bind.txt` tables and `win32u.prx`, and uploads
  and verifies them in `--prx-only`.

**Later:** `libfreetype.prx` and the fonts (d3), the d4 pixel rules, d's `--fb` pixels.

## Not tested by d

The HDMI output (no capture stick: framebuffer only), USB keyboard and mouse, audio, 32-bit,
`WINE_PS5_SERVER_DIRECT=1`. Every LOG line says which of these it did not test.

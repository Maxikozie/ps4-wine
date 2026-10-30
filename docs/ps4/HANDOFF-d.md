# Hand-off: milestone d (winemine with the DS4)

Written 2026-10-30. Read `CLAUDE.md`, `HANDOFF-c.md` (how c was reached), then this. The plan
splits d into five sub-steps, riskiest first. Each has its own `PS4WINE dN` line and its own
`check.sh dN` rule. The milestone's own rule (`check.sh d`) is the last of them. **d1 passed on
its first launch (2026-10-30 14:45); d2 is next.**

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

### d2: win32u inside Wine, offscreen GDI, the user driver installs

**Host first:**
- A host Wine with `WINE_PS5_USER_DRIVER` and `WINE_INPROCESS_SERVER`, in its own build dir so the
  prefix's host Wine is untouched.
- `tools/test_wine_ps5_driver.sh`: the fixture's header names it, but it is not in the fork.
- `tests/wine_ps5_driver_sink.c` changed to send relative moves. Patch 0670 made type 2 relative,
  and the pointer starts at the frame centre.
- New `tests/wine_gdi64.c` (PE64) does `GetSystemMetrics`, a 64×64 DIB section filled orange,
  `GetPixel`, an `EnumFontFamilies` count, and shows a window for 2 s.

**Console:**
- ntdll's `dlopen("win32u.so")` takes the d1 binding.
- The title sends `pw_wine_set_present_sink` frames (BGRA) to `pw_videoout_orbis`, swapping to
  R,G,B,A in the copy.
- `runtime.sh` stages `win32u.prx`.
- `prefix.sh` adds `gdi64.exe` and refuses a `user.reg` with `MenuHeight` (patch 0410).

**Line:** `PS4WINE d2 gdi win32u=ok pixel=ff8000 exit=0 driver=ps5 frames=N fonts=N`
- **Rule:** `win32u=ok`, `pixel=ff8000`, `exit=0`.
- **Recorded:** `frames` and `fonts` (0 expected before d3).

### d3: FreeType and fonts

- FreeType 2.13.3 as `libfreetype.prx` (orbis-clang), exporting the 31 functions win32u looks up.
  The PS5 recipe is in the fork's `docs/WINE_PS5_BUILD.md`. It gets its own pin and a
  `THIRD_PARTY.md` row.
- The pinned Wine tree's 13 `fonts/*.ttf` go to `share/wine/fonts` (`runtime.sh`) and to
  `drive_c/windows/Fonts` (`prefix.sh`), because `/app0` cannot be listed.
- `gdi64.exe` draws "Wg" in Tahoma and counts the ink pixels.
- d2 and d3 share a launch when libfreetype is ready in time.

**Line:** `PS4WINE d3 fonts n=N tahoma=0|1 text_px=N exit=0`
- **Rule:** `n>=13`, `tahoma=1`, `text_px>=50`. The threshold is confirmed by the host run before
  the console run.

### d4: winemine on screen, scripted click, framebuffer pixels

**Host:**
- The driver-sink fixture runs `winemine.exe`.
- A scripted click at a known cell (relative deltas from the centre) opens the board.
- The reference PPMs give two board pixels, mapped through `pw_present_scale_placement` (800×600
  desktop centred in 1080p). They become d4's pixel rules, written into this file and
  `MILESTONES.md` before the run.

**Console:**
- The title starts `winemine.exe`.
- It posts the same click through `pw_wine_post_input` after frame 120.
- It sets `board_opened` from frame hashes before and after the click.
- It writes `shot.raw` 60 frames after the click.

**Line:** `PS4WINE d4 winemine frames=N board_opened=0|1 refused=N fb=ok`
- **Rule:** `frames>=600`, `board_opened=1`, `refused=0`, `fb=ok`, plus the `--fb` pixels.

### d5: the DS4 drives the pointer, which is milestone d itself

- `pw_pad_orbis.c` read loop.
- Bindings from `native/pw_wine_display.c`: `pw_wine_pointer_step` maps the left stick to relative
  `MOUSE_MOVE`, and `pw_wine_game_inputs` maps cross to the left button and circle to the right.
- Host tests under `-DPW_PAD_ORBIS_HOST_TEST`.
- The user plays winemine for about a minute.

**Line:** the milestone line `PS4WINE d winemine frames>=600 inputs>=10 refused=0 board_opened=1`
(`refused` = input events the sink queue dropped), plus `fb=ok`. `check.sh d --fb` adds d4's
pixel rules.

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

# Hand-off: milestone d (winemine with the DS4)

Written 2026-10-30. Read `CLAUDE.md`, `HANDOFF-c.md` (how c was reached), then this. The plan
splits d into five sub-steps, riskiest first. Each has its own `PS4WINE dN` line and its own
`check.sh dN` rule. The milestone's own rule (`check.sh d`) is the last of them. No console run
for d has happened yet.

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

**Two-PRX test** (fork `native/orbis/`, built like `pw_probe_mod`):
- `pw_bind_lib.prx` exports two functions and one data object.
- **Method A, loader imports.** `pw_bind_use.prx` imports the functions through the loader:
  `create-fself -library-path` against the lib's export library; ntdll.oelf already carries
  `DT_SCE_EXPORT_LIB ntdll`. It is loaded both before the lib (does the loader resolve a NEEDED
  PRX itself?) and after it.
- **Data import, kept separate.** `pw_bind_data.prx` imports the data object. It loads last under
  the fault handler, with a progress file, so a fault costs only that stage.
- **Method B, thunk table: the fallback that needs no loader support.**
  - `tools/gen_prx_imports.py` gives each sibling-PRX import a `jmp *slot(%rip)` stub.
  - An exported `pw_prx_bind_imports(resolver)` fills the slots from the exporter's PRXDESC1
    table (`pw_prx_lookup`).
  - It refuses data imports at build time.
  - `pw_bind_thunk.prx` exercises it. It has a host test.

**At scale.**
- `win32u.prx` is built with method A against `ntdll.oelf`. `dlsym`, `dlopen` and the `malloc`
  family become ntdll imports instead of static copies.
- The build writes `win32u.bind.txt` (symbol and GOT offset).
- The title loads win32u.prx after ntdll.prx, without `module_start`, and compares every GOT slot
  with ntdll's descriptor. That gives `w32u_bound=N/78`, which catches wrong NIDs: the PS5's runs
  8–10 had every import 0.

**Title side, same launch:**
- `native/orbis/pw_videoout_orbis.c`: two linear 1920×1080 buffers in Garlic direct memory,
  `A8B8G8R8_SRGB` (0x80002200, as `wsi_orbis.c`). The CPU draws b's test pattern for 120 flips,
  and the flipped buffer goes to `shot.raw` (tmp, fsync, rename as `probes/triangle.c`).
- `native/orbis/pw_pad_orbis.c`: `sceUserServiceGetInitialUser`, `scePadInit/Open/ReadState`.
  The pad data size and offsets are logged, plus whether cross was pressed in the first 10 s (the
  user presses it).
- Then `hello.exe` as in c.

**Line:**
```
PS4WINE d1 bind=import|thunk|none lib=ok import=ok|fail|- order_needed=0|1 data=ok|fault|- thunk=ok|fail w32u_load=<status> w32u_bound=N/78 videoout=ok fb=ok hello=ok pad=ok|none pad_cross=0|1
```

**Rule:**
- `bind` is `import` or `thunk`;
- `videoout=ok`, `fb=ok`, `hello=ok`;
- `--fb` pixels `960,540 = 0,255,0` and `240,135 = 255,128,0`.
- Pad fields are recorded, not gated.

**Decision:**
- Keep method A if `w32u_bound=78/78` and the import works.
- Otherwise use method B for win32u (and later winevulkan).
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

- **`check.sh`:**
  - `d1`–`d5` as milestone ids. The grep is already `PS4WINE $MS `, and logs are `logs/*-d1.log`
    and so on.
  - An `in` op for `bind`.
  - `HAS_PIXEL` for d1, d4 and d.
- **`check_d_test.sh`:** `tests/check_d_test.sh` with `tests/fixtures/d1-*.log` … `d-*.log`
  (pass, fail and nolog cases, plus the generated PNGs `check_b_test.sh` uses), wired into
  `build.sh probe-test`.
- **Build scripts:**
  - `build_native_orbis.sh` links `-lSceVideoOut -lScePad` and builds the four bind PRXs.
  - `runtime.sh` stages them, plus `win32u.prx`, `libfreetype.prx` and the fonts, and verifies
    their sizes in `--prx-only`.

## Not tested by d

The HDMI output (no capture stick: framebuffer only), USB keyboard and mouse, audio, 32-bit,
`WINE_PS5_SERVER_DIRECT=1`. Every LOG line says which of these it did not test.

# Hand-off: milestone g (Bloodlines, 32-bit D3D9 under WoW64 and DXVK 2.6.2)

Written 2026-11-01, after phase p (repo `fbd6853`). Read `CLAUDE.md`, then this, then `MILESTONES.md` (the g row
and note), `HANDOFF-p.md` ("Resume here") and `HANDOFF-f.md` ("Games on the host", the PE image table).

## Resume here (2026-11-02 04:40: the pointer over DXVK and the DS4 alone in play; gpad owes the L1 layer)

**State at the end of 2026-11-02's session (LOG.md 03:25-04:37):**

| Step | Result |
|---|---|
| Icon | Wine's logo in every package (`assets/icon0.png`, `pkg.sh` default) |
| gc1 | **PASS** |
| gc2 | **PASS** (the cursor port in libvulkan.prx) |
| g1m, g1, e | **PASS** on that runtime: the runtime on the console now, `runtime.sh --prx-only` 03:27 |
| gc (L14) | **PASS**: the pointer over Bloodlines' menus; g2 again; first gameplay (Jack's tutorial, ~55 fps), from a save |
| gpad (L15) | **FAIL by its rule only on `layer_keys=0`**, with title `ps4-wine-c76b600+dirty.pkg` (installed) |

L15 in detail:
- **Worked:** walking and running with the left stick, the taps, the crouch latch. Nothing stuck, no keyboard.
- **The user's verdict:** "perfect".
- **Owed:** no L1 binding was used before the line, and the 3rd-person HDMI frame was not taken.

**Next session, in order:**
1. **Finish gpad.** Launch Bloodlines, answer a dialogue with L1 + a face button, and switch to 3rd person with a
   ranged weapon out or holstered. Then `check.sh gpad` on the last gpad line, with the HDMI frame. Nothing to
   build: the title and preset are on the console.
2. **g itself.** New game and character creation with the DS4, then the touchpad mark in the first map. The window
   bug is fixed in c76b600+dirty.
3. **Notes**, still open:
   - the USB mouse research;
   - the PS-button suspend kill (`0xa0d0c00a`: after it, check `/data/ps4-wine/g/progress.txt`);
   - audio cutouts during the movies;
   - load time (~100 s for the first map);
   - typing on terminals (needs an on-screen keyboard);
   - whether the game hides the cursor in gameplay and dialogue (no end-of-session counters yet: every session so
     far ended by suspend).

**Console now:** `env.txt` = `PS4WINE_MILESTONE=g`, `PS4WINE_AUDIO=on`, `WINEDEBUG=+loaddll`. `profiles/vtmb.ini` and
the new `input/vtmb.input` are pushed.

## Earlier: 2026-11-02 02:35 (Bloodlines reaches its menu with sound (g2 PASS); blocked at character creation by input)

**Where it stands.** Bloodlines (UP 11.5) starts on the PS4, plays its intro movies with sound and shows its main menu
at 1920x1080 through DXVK at 60 Hz (g2 PASS twice: L12, L13). New Game reaches character creation, and there it
stops: no cursor is drawn over DXVK's frames, so the pad pointer moves blind, and the USB mouse gives no data. The g
window (the second mark in the first map) was never reached.

**Console launches since the last handoff (LOG.md 00:43-02:32):**

| Launch | Result |
|---|---|
| g1m trace (00:43) | the -1's cause: RADV advertised `VK_EXT_map_memory_placed` only with KMS/DRM |
| g1m, g1, e (00:51-00:59) | **PASS** with mesa-ps4 0003 advertising the extension on `__PS4__` |
| L5 Bloodlines (01:16) | FAIL: "Failed to load the loader DLL: No access to memory location" (the UP's `loader.dll`) |
| trace (01:21) | the same; cause found on the host (below) |
| g1m, g1, e (01:48-01:54) | **PASS** on the runtime with fork patches 1120 and 1130: **the runtime every later launch ran on** |
| L10 (02:02) | past the loader; black menu: 800x600 swapchain refused by VideoOut (`0x80290005`, INVALID_RESOLUTION) |
| L11 (02:05) | no game: the stage tracker resumed L10's open stage as a crash |
| L12 (02:13) | **g2 PASS**: the main menu (ResPatch 1920x1080); silent (plan g had no audio stage) |
| L13 (02:32) | **g2 PASS with sound** (new title); character creation reached; blocked: no cursor, no mouse data |

**Fixed this session:**
- **mesa-ps4 0003** also advertises `VK_EXT_map_memory_placed` on `__PS4__` (it was under `MESA_SYSTEM_HAS_KMS_DRM`), so
  win32u takes the placed path: 32-bit maps work (vk32, d3d9tri32, Bloodlines). The SDK libc's `sysconf` and
  `getpagesize` both give 16384, so the advertised alignment is right.
- **Fork patch 1120** (`ntdll: clear decommitted pages beside a read-only page`) and **1130** (`ntdll: keep a hot host
  page whole beside a read-only page`): two faults in prospero-win's patch 0974 with 16 KiB host pages. The UP's
  `loader.dll` maps a module itself, makes one page read-only and decommits/fills the pages beside it. Wine's own
  decommit memset faulted on the read-only neighbour (1120), and after 256 stepped writes 0974 reported a fake write to
  the read-only page, which the loader took for a real access violation (1130). Reproduced and verified on the host
  with `WINE_HOST_PAGE_SIZE=16384`; `tests/wine_subpage_protect.c` covers both. Upstream #739 (0986) does not fix it.
  Cost of 1130: while a host page is kept whole, a write to its read-only page is not seen (emulators that watch code
  pages lose that fault).
- **Console data:** the prefix's `HKCU\Software\Troika\Vampire\ResPatch` set to 1920x1080 by hand (the game wrote its
  800x600 default on the first run; backup of the old file in the session scratchpad); `profiles/input/vtmb.input`
  rewritten from the game's `default.cfg` (R3 feed `f`, L3 `[` = invnext; the old R3 sent F5 = `slot4`;
  `mouse_speed` 600); `profiles/vtmb.ini` `show_fps = true` (DXVK's HUD from the next launch: its cost is in every g
  number from then on).
- **Title** (`ps4-wine-b0d5f17+dirty.pkg`, installed): plan g opens the audio port as p5 does (`PS4WINE_AUDIO=off`
  turns it off); the g line has `audio grains grains_nonzero audio_errors mouse_reads mouse_records mouse_rc
  mouse_count`; the mouse reader logs `sceMouseRead`'s results, halves a refused count and reopens per device after
  ~1 min of empty merged reads; `threads_live` reads correctly.
- **check.sh:** with no PS4WINE line, MESA `info:` lines no longer count as a crash.

**The pad step, 2026-11-02 04:00: Bloodlines on the DS4 alone.** In L14 the cursor step passed (gc, and g2
again) and the user reached Jack's tutorial from a save. The DS4 still could not walk with a stick (WASD on the
d-pad) or answer dialogue (number keys: the USB keyboard's `1`), and square and triangle were still the title's
segment marks (one opened by accident). So the title gets a pad mapper:
- **Fork changes** (title-only: no runtime change, no g1m/g1/e reruns):
  - upstream #736's `keyboard_stick`, ported, plus `stick_walk`/`stick_run`;
  - an L1 layer (`layer`, `<layer>+<button>`);
  - tap/hold (`<button>.hold`, `hold_ms`);
  - latches (`toggle:<key>`) and chords (`ctrl+c`);
  - all in `pw_wine_pad_map_step` (`native/pw_wine_display.c`), host-tested with a 10k-step fuzz against a shadow
    keyboard.
- **Shared keys are counted.** A latched ctrl survives a ctrl+c chord, and the walk shift survives a shift chord.
- **The touchpad keeps the marks.** A tap marks, on the release. Touchpad + square starts the interior segment and
  touchpad + triangle the hub segment, and those presses never reach the game.
- **Also fixed: the g window ended as it began.** In L14 the second mark emitted `PS4WINE g` at once with
  `window_s=0`. `g_script`'s `now`, read at the top of the loop, was older than the `g_window_ns` its own mark had
  just stamped, so the uint64 difference wrapped.

| Button | Action | With L1 held |
|---|---|---|
| Left stick | WASD; a light push also holds shift (walk), past 80% runs | |
| Right stick | the mouse: look and the pointer | |
| R2 / L2 / R1 | attack (mouse_left) / block (tab, held) / cast discipline (mouse_right) | R2 still attacks / ctrl+c (hack) / 9 |
| Cross / Triangle | use (e) / jump (space) | 1 / 4 |
| Square | tap reload (r), hold holster (h) | 3 |
| Circle | tap inventory (i), hold character sheet (c) | 2 |
| L3 / R3 | crouch latch (toggle:ctrl) / 1st-3rd person (z) | f8 end disciplines / f9 quick save |
| D-pad up/down/left/right | feed (f) / weapons↔disciplines (t) / previous (]) / next ([) | 5 / 7 / 8 / 6 |
| Options | escape (menu) | l (quest log) |
| Touchpad | marks (tap); + square/triangle: segments | |

**Rule `check.sh gpad`, fixed before its first run.** It reads plan g's last `PS4WINE gpad vtmb` line, which comes
every 60 s with the mapper's cumulative counters.
- **Gate:** `stick_keys>=4 walk_s>=1 layer_keys>=1 stuck=0 kbm=0 faults_unresolved=0`.
- **Evidence:** the user's word that they walked and ran with the stick, answered Jack with L1 + a face button and
  switched perspective with R3, plus an HDMI frame of 3rd person. That frame needs a ranged weapon out or the
  weapon holstered: with melee or fists the game forces 3rd person and z does nothing.

**Not tested:**
- dialogue past 9 answers;
- whether the game drops crouch across a level load while the latch holds ctrl. If it does, the fix is plain
  hold-to-crouch on L3;
- hold timing under load stutter.

Taps fire on the release, then stay held 20 ms.

**The input step, started 2026-11-02 03:00: the cursor first, then the USB mouse research.**

The cursor is ported in three sub-steps. Each rule was written into `check.sh` (with fixtures in
`tests/check_g_test.sh`) before its first run.

- **gc1: the four calls, title only** (plan `gc1`, fork `native/orbis/pw_cursor_probe_orbis.c`).
  - The title opens its own VideoOut and flips a green 1920x1080 frame every vblank.
  - It takes 64 KiB of Garlic for the images, as the PS5 does (2 MiB alignment if 64 KiB is refused).
  - It writes test image A and image B (`wine/orbis/pw_videoout_cursor_orbis.h`), then runs 8 states of 6 s.
    White bars at the bottom left number each state, so any frame of the recording names its state:

    | State | Call |
    |---|---|
    | 1 | none (green only) |
    | 2 | `Enable(A)` + `SetPosition(928,508)`: **the gated state** |
    | 3 | `Enable(A)` again while enabled, `SetPosition(100,100)` |
    | 4 | back to (928,508), `SetImageAddress(B)` |
    | 5 | `SetPosition(1900,1060)` (partly off the frame) |
    | 6 | `Disable` |
    | 7 | `Enable(A)` again at (928,508) |
    | 8 | port closed with the cursor shown, reopened, no call; then `Disable` on the new handle |

  - Line: `PS4WINE gc1 cursor cursor= mem= mem_align= mem_rc= enable= position= image= disable= enable_twice=
    position_moved= position_back= position_edge= enable_again= reopen= reopen_disable= flips= flip_errors= hello=`.
  - Statuses read `0` or hex.
  - `IsUpdatePending` is left out: its PS4 arguments are unknown.
- **gc2: the port, a runtime change.**
  - Plan `gc2` runs e1's stages, but `pw_vk_present_frames` presents 900 + 360 frames.
  - After every present it calls libvulkan.prx's `pw_videoout_cursor`, looked up as win32u does, with image A:
    - frames 0-299 at the test place, 300-599 at (100,100), then hidden;
    - once between the swapchains (expected 1, no output);
    - at the test place again in the second swapchain.
  - Line: `PS4WINE gc2 vkcursor present= frames= ... cursor_export= cursor_shows= cursor_reopen_shows= cursor_hides=
    cursor_noout= cursor_errors= cursor_rc= vk_cursor_updates= vk_cursor_rc= vk_cursor_format= fb_cursor= release= hello=`.
  - `fb_cursor` is RADV's readback at 944,524, recorded: cyan means the cursor is VideoOut's plane, not part of the frame.
- **The port** (fork `wine/orbis/pw_vulkan_radv_orbis.c`, the PS5's section):
  - **Handle.** `--wrap=sceVideoOutOpen` and `--wrap=sceVideoOutClose` (new: mesa-ps4 opens and closes VideoOut per
    swapchain) keep the handle. The cursor state goes with a closed handle.
  - **Image.** It is cut to 64x64 and converted by `PW_CURSOR_ORBIS_FORMAT` (0 until gc1 measures the plane).
  - **Position.** It maps onto the last swapchain's extent (mesa-ps4 has no `wsi_videoout_present_rect`).
  - **Exports.** `pw_videoout_cursor` and `pw_vulkan_cursor_stats` are in libvulkan's descriptor
    (`tools/build_wine_orbis.sh`).
- **gc: Bloodlines' menu with the pointer.**
  - Plan g emits `PS4WINE gc vtmb menu= cursor_stats= cursor_calls= cursor_shows= cursor_updates= cursor_hides=
    cursor_noout= cursor_errors= cursor_rc= cursor_at=x,y cursor_output= cursor_format= faults_unresolved= exit=`
    beside g2 at the first mark.
  - The Vulkan plans also log the counters at their end (a `PW_MS step cursor at the end:` record, not in their lines).

**The rules** (`check.sh`, fixed 2026-11-02 before the first gc runs). Test image A sits at 928,508. The centres
of its quadrants are 944,524 (white), 976,524 (black), 944,556 (red) and 976,556 (alpha 0).

| Step | Gate |
|---|---|
| gc1 | `mem=ok enable=0 position=0 image=0 disable=0` + HDMI `--shot` (state 2): `944,524=255,255,255`, `976,524=0,0,0`. White and opaque black read the same in either channel order. **Recorded:** the order (944,556 red or blue), the alpha rule (976,556 green straight, white additive, magenta ignored), image B's blend, the position units, the edge and the reopen |
| gc2 | `present=ok frames>=300 gpu_hang=0 swapchain=1920x1080 cursor_export=ok cursor_errors=0 cursor_shows>=1 cursor_reopen_shows>=1 cursor_noout>=1` + HDMI `--shot` (first 5 s): `944,524=255,255,255 976,524=0,0,0 944,556=255,0,0 976,556=0,255,255` |
| g1m, g1, e | unchanged, run again on gc2's runtime |
| gc | `menu=1 cursor_shows>=1 cursor_errors=0 faults_unresolved=0 exit=running`. **Evidence, not gated:** an HDMI frame of the menu with the pointer, and the user's word that the pointer shows, follows the pad and works at character creation |

Both cursor rules are HDMI only: `check.sh` refuses `--fb` for them, because the cursor is not in the framebuffer.

**gc1 PASSED (LOG.md 03:25).** Every call returned 0, and the 64 KiB Garlic block was accepted at 64 KiB
alignment. Over HDMI, the PS4's cursor plane behaves as the PS5's:
- **Format:** it reads win32u's straight-alpha ARGB words. Red stays red (236,0,0), and alpha 0 shows the frame.
- **Blending:** half alpha blends straight (125,255,119 over green).
- **Position:** in frame pixels, 1:1, clipped at the frame's edge.
- **Closing:** a closed port takes the cursor with it.

So the port converts nothing (`PW_CURSOR_ORBIS_FORMAT 0`). The evidence is the HDMI frames
`logs/20261102-gc1-state{2,3,4,5,8}.png` and the 44 s clip `20261102-gc1-states.mkv`.

**Order of the launches:**
1. gc1 on the new title (`ps4-wine-0a8ddb7+dirty.pkg`, with Wine's icon). Done: PASS.
2. The port with gc1's findings: `build.sh wine --skip-host` + `runtime.sh --prx-only`.
3. gc2.
4. g1m, g1, e.
5. Bloodlines (`gc` + `g2`), then character creation.

**Not tested by these steps:**
- a cursor larger than 64x64 (it is cut);
- a swapchain smaller than the desktop (host test only);
- the cursor across a suspend;
- the second cursor index;
- `SetHotSpot` and `2xMagnify`.

**Next session, in order** (as written at 02:35):
1. **The cursor over Vulkan frames (blocking).** Fork patch 0740 (win32u) hands the cursor to libvulkan.prx's
   `pw_videoout_cursor` after each present; the PS5's libvulkan.prx has it (`wine/ps5/pw_vulkan_radv.c:33`, VideoOut's
   hardware cursor), the Orbis one (`wine/orbis/pw_vulkan_radv_orbis.c`) does not, so win32u's `dlsym` finds nothing.
   The PS4 SDK stub has `sceVideoOutCursorEnable/Disable/SetImageAddress/SetPosition`. Port it; it needs the WSI's
   VideoOut handle (mesa-ps4 `wsi_orbis.c`) and GPU-visible memory for the image. A runtime change: g1m, g1 and e
   again before Bloodlines.
2. **The USB mouse:** `sceMouseRead` returns 0 records on every read, merged (`open=0x2f0700`) and per device
   (`open=0x300700`), never an error; the keyboard reads fine; the system shows the mouse as connected. The only other
   PS4 notes (ps4-mesa-docs' RetroArch port) never called past `sceMouseInit`. To research: `sceMouseOpen`'s type/index
   arguments and param layout on the PS4, the read's record layout, any focus/privilege call.
3. **The PS button kills the title:** suspending it ends in `0xa0d0c00a` (CPU_FAULT_SUBMITDONE_TIMEOUT_IN_SUSPEND_ASYNC);
   the next launch then spends itself resuming the open stage as a crash. Until fixed: after a PS-button close,
   `rm /data/ps4-wine/g/progress.txt` over FTP. The fix is the title's (answer the suspend, or SubmitDone).
4. **Audio cutouts** when the pad pointer moves during the intro movies (the movies take Wine's desktop path; each
   pointer move redraws the desktop: unmeasured). Add the driver's `underruns` to the g line.
5. **Load time:** ~60 s from `Vampire.exe` to the first menu present (DLLs 8 s; movies, data and DXVK's first pipelines
   not separated: the per-thread census is off on this firmware).
6. **Pad:** Cross is jump, so menus need R2; porting upstream #736 (`keyboard_stick`, title-only: `src/pw_game_profile`,
   `native/pw_wine_display`, the two Orbis pad loops, ~45 min with tests) frees the d-pad for holster, quicksave,
   block and previous.
7. **The WSI's fallback buffers** at the display's size (a game asking 800x600 still gets a black screen): not blocking
   while ResPatch says 1920x1080.

**The user's rules (2026-11-02):**
- A runtime change (PRXs, mesa-ps4, orbis-compat) is followed by g1m, g1 and e on it before any Bloodlines launch; a
  title-only reinstall is allowed.
- No mesa-ps4 0004 (GPU busy) and no orbis-compat 0002 (RADV stack knob) yet; their g fields stay `-`.
- The user plays Bloodlines on the laptop from `build/host-game/vtmb` (prefix `build/prefix-desktop`): host tests run
  `Vampire.exe` only from the reflink copy `build/host-test/vtmb` with their own prefix, and never wait on or stop
  processes by name.

**On the console:** Bloodlines, `profiles/vtmb.ini` (show_fps true) and `input/vtmb.input` (mouse_speed 600), the
runtime of 01:43, the title `ps4-wine-b0d5f17+dirty.pkg`, the prefix with ResPatch 1920x1080 and `config.cfg` equal to
`default.cfg`, `env.txt` = `PS4WINE_MILESTONE=g`, `PS4WINE_AUDIO=on`, `WINEDEBUG=+loaddll`; `/data/ps4-wine/g/progress.txt`
removed (the next launch starts a fresh cycle).

**Recorded-only findings:** the netlog loses about half its records under `+vulkan` or `+virtual` (use the host for
traces); FTP returns `.prx` files decrypted (compare upload times, not hashes); libvulkan's own pthread layer still
raises RADV's threads to its 16 MiB floor (6-9 threads, 96-144 MiB of flexible memory; free flexible memory fell to
152 MiB at character creation in L13); `check.sh` takes a klog `0xa0d0c00a` from an earlier, idling title for this
launch's crash when the log starts before the close (trim the log to the launch, as L10's line says).

**Upstream boundary, still open:** fork comments and strings that name this repo: `native/orbis/pw_milestone_orbis.{c,h}`,
`pw_hist.h`, `pw_videoout_orbis.h`, `wine/orbis/pw_vulkan_radv_orbis.{c,h}`, `tests/wine_d3d9tri32.c`,
`tests/test_wine_d3d9tri32.py`, the Vulkan app name `"ps4-wine e1"` and the console path `/data/ps4-wine/` in
`wine/wowprospero/unix.c` (functional: renaming moves the console's data). Patches 1080, 1090 and 1110 were reworded.

**Uncommitted (the user commits):**
- Repo: `docs/ps4/{LOG,HANDOFF-g}.md`, `profiles/vtmb.ini`, `profiles/input/vtmb.input`, `scripts/ps4/check.sh`.
- Fork: `wine/patches/1120-*`, `1130-*` (new), `1080`, `1090`, `1110` (reworded), `tests/wine_subpage_protect.c`,
  `native/pw_hid_ps5.{c,h}`, `tests/test_pw_hid_ps5.c`, `native/orbis/pw_milestone_orbis.c`.

## Does g need a desktop host Wine?

**To reach the first map on the laptop by hand: yes.** All three host trees (`.deps/wine`, `.deps/wine-host`,
`.deps/wine-host-drv`) are configured `--without-x --without-freetype` and build no winex11, winepulse or
winealsa. With them there is no window, no sound and no font rasteriser, and input can only be scripted. GOG's
installer under that Wine looped in conhost: with no FreeType there is no console font, and conhost's divide by
zero (`programs/conhost/window.c:629`) started another winedbg.

**For the console gate: no.** The console runs the headless user driver. The headless `wine-host-drv` stays the
closest host model of the console (fork `docs/wine-worker-desktop.md:55-56`: an X11 desktop does not reproduce
the console's desktop ownership).

**What the desktop tree gives g:**
- the first map, played on the laptop;
- `g-int` and `g-hub` saves at fixed spots, for repeatable console segments;
- host crossings per frame and the module census.

**H0, the install** (x86_64 headers only; new WoW64 needs no `:i386` packages):

```
sudo apt install libx11-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev libxfixes-dev \
  libxrender-dev libxinerama-dev libxcomposite-dev libpulse-dev libfreetype-dev libfontconfig-dev
```

Not needed: libvulkan-dev (Wine takes only the soname), wayland, gnutls, SDL.

## What the plan found in the source (not measured)

| # | Finding | Where | Gate path? |
|---|---|---|---|
| 1 | **32-bit Vulkan maps are refused.**<br>• win32u's WoW64 path reserves a low range and asks for a placed map when the device offers `VK_EXT_map_memory_placed` (`dlls/win32u/vulkan.c:507-520,1125-1176`). **Corrected 2026-11-02:** RADV offered it only with KMS/DRM (`radv_physical_device.c:954`, `#if MESA_SYSTEM_HAS_KMS_DRM`), so on the PS4 win32u fell back to RADV's high mapping and refused it; 0003 now advertises it on `__PS4__` (Resume here).<br>• mesa-ps4's `ac_drm_bo_cpu_map` refuses any requested address ("cpu_map at a fixed address is not supported here", `ac_orbis_drm.c:7713`), and `has_userptr` is false on the PS4 (`ac_gpu_info.c:1116`).<br>• So 32-bit DXVK can map no host-visible memory. prospero-win's PS5 drivers map through a low CPU alias (fork `docs/WINE_PS5_BUILD.md:756-761,878`) | mesa-ps4 | yes |
| 2 | **No `ws2_32.prx`.** `ws2_32`'s `DllMain` returns `!__wine_init_unix_call()` (`dlls/ws2_32/socket.c:731`), and the game imports `ws2_32` and `wsock32` | `build_wine_orbis.sh` | yes |
| 3 | **No arguments or working directory.** Wine's argv is always `{"wine", exe}`, `PS4WINE_EXE` is cut at the first space (`wine64_main_orbis.c:148,506-510`), and `pw_cwd_set` is exported but unused. The PS5 title does both (`native/wine64_main.c:1253-1259,1376-1388`, `src/pw_wine_launch.c`) | title | yes |
| 4 | **The prefix and uploads.**<br>• The prefix stages only DXVK's x64 `d3d11`/`dxgi` (`prefix.sh:74-94`); the pinned tarball has `x32/d3d9.dll`.<br>• `prefix.sh` puts files one at a time, and its mirror checks 8 files: no tool uploads and verifies 21k files (4.1 GiB) | scripts | yes |
| 5 | **No USB keyboard or mouse on Orbis.** The PS5 reader is `native/pw_hid_ps5.c`; OpenOrbis v0.5.4 ships `orbis/Keyboard.h`, `orbis/Mouse.h`, `libSceKeyboard` and `libSceMouse` | title | no: the DS4 preset can reach gameplay |
| 6 | **No g measurements in the title.**<br>• No `fps_avg` and no `crossings_per_frame`: the batch counters are `PW_VK_BATCH` lines, one per present, cumulative (`pw_vk_batch_pe.c:323`), reaching the title through `wine_output_sink` (`wine64_main_orbis.c:225`).<br>• No CPU time per thread: orbis-compat answers CPU-time clocks with the monotonic clock (`pw_milestone_orbis.c:760-767`), and p1 used `getrusage(RUSAGE_THREAD)`, the caller's own time. `HANDOFF-p.md`'s "p1's instrumentation" says `CLOCK_THREAD_CPUTIME_ID`: stale.<br>• No GPU time.<br>• `flex_mib` is read at the line only.<br>• No live thread count: `nb_threads` is static (`dlls/ntdll/unix/thread.c:84`) | title, ntdll, mesa | `fps_avg` and `crossings_per_frame` only |
| 7 | **The "long scan-out copy" in e's runs (125, 161, 293 ms) is the screenshot.** `wsi_orbis_shot` writes 8 MiB and fsyncs inside the WSI's timed window ("shot of present 300 … (292 ms)" then "worst 292780 us": `logs/20261101-221227-p6-L4-e.log` lines 749/754; the 21:19 run at 783/788). The zero-copy path itself takes 2-6 µs | patch 0002 | no |
| 8 | **RADV's 6 threads.**<br>• Identified: two futex self-test threads (`ac_orbis_drm.c:2419,2698`) and two disk-cache queues (`radv_physical_device.c:3089/3092`, each can grow to 4). The other 2 are unknown.<br>• Mesa passes no attributes, so all are raised to libvulkan's floor (16 MiB, from Wine's main thread). That floor is "not configurable" (`orbis_thread.cpp:115`) | orbis-compat | no |
| 9 | `check.sh g` exists (`check.sh:251`) with no STAGES entry, fixtures or test | scripts | yes |

**Also read:**
- `Vampire.exe` is large-address-aware (characteristics 0x012e); `Vampire.exe.12` is not.
- Below 4 GiB, before Wine, only the eboot is mapped (f1).
- The game's images import `kernel32 user32 winmm advapi32 gdi32 wsock32 shell32 oleaut32 ole32 ws2_32 shlwapi
  dinput8 dbghelp d3d9`. Every one is an i386 PE module in the runtime. Input goes through DirectInput 8.
- The UI fonts (`resource/trackerscheme.res`) are Tahoma and Marlett (Wine ships both), Times New Roman and
  Trebuchet MS (substituted), and the game's own `Vamp_*`.

**Measured before g (milestone a, `probes/probe.c:566-593`, `logs/20261030-001125-a.log`):**
- **Aliasing works.** One direct-memory block mapped twice (0x208400000 and 0x209400000) aliased (`alias=1`).
- **MAP_FIXED inside a reservation works** (`map_fixed=1`).
- Both were measured above 4 GiB at 2 MiB alignment, which is the mechanism of the placed-map fix.

## DXVK 2.6.2's `vampire.exe` profile

**The entry**, read 2026-11-01 from `src/util/config/config.cpp` at tag v2.6.2. It is matched with
`std::regex::extended | icase`, so it applies to any path ending in `\vampire.exe`:

```
    /* Vampire - The Masquerade Bloodlines        */
    { R"(\\vampire\.exe$)", {{
      { "d3d9.deferSurfaceCreation",        "True" },
      { "d3d9.memoryTrackTest",             "True" },
      { "d3d9.maxAvailableMemory",          "1024" },
    }} },
```

| Key | Profile | Default | What it does in 2.6.2's code |
|---|---|---|---|
| `d3d9.deferSurfaceCreation` | True | false | **Without the flag:** the `Presenter` constructor creates the VkSurfaceKHR at swapchain creation (app thread). **With it:** `Presenter::recreateSwapChain` creates the surface and the swapchain together at the first `acquireNextImage`, which `D3D9SwapChainEx::PresentImage` calls on the app thread inside the first `Present`. A device `Reset` then creates no surface; the next `Present` calls `invalidateSurface()`, and the next acquire destroys and rebuilds both |
| `d3d9.memoryTrackTest` | True | false | **On a non-Ex device, image creation can fail.** Texture and surface creation return `D3DERR_OUTOFVIDEOMEMORY` once the tracked counter is exhausted (`ChangeReportedMemory`: `return !memoryTrackTest \|\| availableMemory >= delta`). A failed request still decrements the counter.<br>**Counted:** non-managed images (D3DPOOL_DEFAULT textures, surfaces, back buffers).<br>**Not counted:** managed, system-memory and scratch pools, and buffers |
| `d3d9.maxAvailableMemory` | 1024 | 4096 | **The budget.** The counter starts at min(sum of the device's heaps, 1024 MiB − 1) (`DetermineInitialTextureMemory`). `GetAvailableTextureMem` returns it, clamped at 0 and rounded to whole MiB |

**The threads** (2.6.2 source):
- `vkQueuePresentKHR` runs on `dxvk-submit` (`DxvkSubmissionQueue::submitCmdLists` → `Presenter::presentImage`).
- The CS thread is `dxvk-cs`; `dxvk-queue` only signals frames.
- The app thread acquires the image in `PresentImage`.
- The thread names come from `env::setThreadName`, so they reach Wine as `SetThreadDescription`.

**What this means on the PS4:**
- **The display hand-over moves.** The title releases VideoOut when Wine creates its first surface. Under this
  profile that happens at Bloodlines' first `Present`, not at device creation as in e.
- **The game may get less than 1023 MiB.** RADV's heaps come from the arena (`ORBIS_ARENA_MIB`, 1 GiB by
  default); if they sum to less, the budget shrinks with them. g records `heaps_mib` and counts DXVK's
  out-of-memory lines.
- **No 32-bit d3d9 option exists.** The only 32-bit branch is the staging wait (`WaitStagingBuffer`: 16 MiB
  instead of 64).
- **g1 runs `d3d9tri32.exe` with these three settings** (`DXVK_CONFIG_FILE=C:\g1\dxvk.conf`, a copy of the
  entry). Its name does not match the regex, so g1 tests what Bloodlines will run.

## The rule, fixed before the first g run

`check.sh g`:

```
PS4WINE g vtmb batch=1 gameplay=1 crossings_per_frame<=2000 fps_avg>=20 session_s>=300 faults_unresolved=0
```

Plus an HDMI frame of the first map, kept as evidence (no pixel gate), and the user's confirmation by eye noted in
the LOG line. The only change from the earlier MILESTONES rule is `gameplay=1`.

| Field | Definition |
|---|---|
| `gameplay` | 1 when the user pressed the **mark** (DS4 touchpad) with the player in control in the first playable map, after new game and character creation. The 300 s window starts at the mark |
| `batch` | 1 when the last `PW_VK_BATCH` record in the window has `enabled=1 negotiated=1` and `records>0` |
| `crossings_per_frame` | Δ`wine_unix_crossings` / Δ`present` between the first and last `PW_VK_BATCH` records in the window, parsed in `wine_output_sink`. It counts winevulkan's crossings only, not every syscall. The records come every 60th present (`PW_VK_BATCH_STATS_EVERY=60`); the counters are cumulative, so nothing is lost |
| `fps_avg` | RADV's present counter (`pw_vulkan_stats`) over the window ÷ 300 s. Each D3D9 `Present` is one `vkQueuePresentKHR`. A loading screen inside the window counts, so the user stays in the map. This replaces the earlier "DXVK HUD counter mirrored into the alive record", which does not exist |
| `session_s` | Seconds from the mark to the line. The title emits the line at mark + 300 s and keeps running |
| `faults_unresolved` | As in f and p |

## Recorded, not gated (a failed source gives `-`)

These fields go on the g line (over the window) and on each segment record.

| Area | Fields |
|---|---|
| Flexible memory | `flex_mib_start`, `flex_mib_min`, `flex_mib`. The `alive` record gains `flex`, sampled each second |
| Threads | `threads_live_peak`, `threads_live` (Wine's `nb_threads`, through a new ntdll export; the peak is kept at the increment, `thread.c:1345`); `threads_created`, `threads_kept`, `threads_small`, `threads_keep_refused`; `vk_threads_created`, `vk_threads_raised`, `vk_stack_floor_kib` |
| Main thread | `main_cpu_us_avg`, `main_cpu_us_p95`: Wine's main thread, which is the game's main thread under WoW64. Δ CPU ÷ Δ presents per 1 s window; the analogue of p1's `guest_cpu_us` |
| DXVK threads | `cs_cpu_us_avg` (`dxvk-cs`), `submit_cpu_us_avg` (`dxvk-submit`, the presenting thread), `other_cpu_us_avg` (the rest) |
| GPU | `gpu_us_avg`, `gpu_us_p95`: GPU busy time per frame. Also `ib_dw_max`, the largest submission against the 2 MiB (524288-dword) cap |
| Frames | `frame_us_avg/p95/max` (p1's `pw_hist` on present intervals), `hitches_50ms`, `wsi_us_max` |
| Memory | `dmem_low_peak_mib`, `dmem_peak_mib`, `heaps_mib`, `dxvk_oom` |
| Sound | `audio_driver`, `grains_nonzero`, `underruns` |
| Run | `cpu=native\|translator`, `input=kbm\|pad`, `exe_base` |

**Per-thread CPU.**
- The title reads every thread once a second through `sysctl(KERN_PROC_PID | KERN_PROC_INC_THREAD)`: `ki_tid`,
  `ki_tdname` and `ki_runtime`.
- Wine names native threads on Linux and macOS only. A fork patch adds an Orbis branch to
  `set_native_thread_name`, so DXVK's names reach the kernel. The title tags Wine's main thread itself.
- If g1's `cpu_probe` finds the sysctl refused, the CPU fields are `-` in g. The fallback (threads sampling
  themselves with `getrusage(RUSAGE_THREAD)`) waits until after g.

**GPU busy.** mesa-ps4 patch 0004 sums each submission's GPU busy span per present: GPU-written timestamps if
`ac_orbis_drm.c`'s submit path allows them, else submit to observed completion (DXVK waits on every fence).

**Segments: the hub and an interior.** After the g line the session keeps running:
- **square** on the DS4 starts an interior segment, **triangle** a hub segment;
- each is 10 s of warm-up, then 60 s with the player standing still, with inputs counted (`seg_inputs`);
- each gives a `PS4WINE gseg vtmb seg=int|hub ...` record with the fields above;
- the g line carries the latest `int_*` and `hub_*` taken before it, or `-`;
- the spots come from the host-made saves `g-int` and `g-hub`, so runs compare like with like, as in p.

The touchpad, square and triangle are reserved for marks and are never bound to game keys.

## Host first (the gate path before the recorded work)

**H0** (the user): the apt install above.

**H1: the desktop tree.** A new `build.sh wine-desktop` wraps
`PROSPERO_WINE_CONFIGURE_EXTRA=ac_cv_lib_soname_vulkan=libvulkan.so.1 tools/build_host_wine.sh --work
.deps/wine-host-desktop`.
- Check `config.log`: X11, PulseAudio and FreeType found.
- Check the build: `winex11.drv` and `winepulse.drv` built, the batch code staged.

**H2: the host game and prefix**, `scripts/ps4/host-game.sh` (`--help`, `set -euo pipefail`).
- **Game copy:** `build/host-game/vtmb` via `cp -a --reflink=auto` (games/ is only read).
- **Prefix:** `build/prefix-desktop` (wow64) with DXVK `x32/d3d9.dll` in `syswow64`, SHA-checked as `prefix.sh`
  does.
- **Run settings:** `WINEDLLOVERRIDES=d3d9=n`, the native CPU, `PW_VK_BATCH=1`, `PW_VK_BATCH_STATS=1`,
  `DXVK_HUD=fps,frametimes,gpuload`.
- **Modes:** `--census` adds `+loaddll`; `--saves-out` copies the saves.

**H3: the user plays on the laptop.**
- New game → character creation → the first map, then on to `sm_hub_1`.
- Two saves at fixed spots: `g-int` and `g-hub`.
- Recorded here:
  - the module census: every DLL with its base, and the Unix libraries missing from the Orbis PRX list (`ws2_32`
    expected);
  - crossings per frame in each place (`tools/summarize_vk_batch.py`).

**H4: the gate path on the headless `wine-host-drv`** (the console's driver code: ps5drv, headless surface, 0910).
- `vk32.exe` (`tests/wine_vk64.c` built for i686): WoW64 `vkMapMemory`.
- `d3d9tri32.exe` (ours) with g1's `dxvk.conf`: its readback gives g1's pixels.
- `Vampire.exe` to its main menu on lavapipe: PPM frames, scripted Esc.
- Then the fallback check: `dinput32.exe` (ours) receives the sink's KEY and relative MOUSE_MOVE as DIK scancodes
  and DIMOFS deltas.

**H5: tests.**
- Fork `make test`: the `PW_VK_BATCH` parser and window maths, the profile's arguments and working directory, the
  stats-sampling knob; then the HID table and the kinfo_proc parser.
- `orbis_prx_report.py` for `ws2_32.prx` and the patched `libvulkan.prx`.
- `tests/check_g1_test.sh` and `tests/check_g_test.sh` with fixtures (pass, `gameplay=0`, crossings over the
  threshold, `fps_avg` under it, a missing field, stage records only), run by `build.sh probe-test`.

## Console: sub-steps and launches

Each rule and its fixtures go into `check.sh` before that step's first launch. One package carries every plan;
launches differ by env.txt only.

**Title stages before Wine, in every g1 launch** (recorded; a failure gives `-`):
- `alias_probe`: what a did not measure. Below 4 GiB, 16 KiB alignment, MAP_FIXED over an existing
  direct-memory mapping inside a reservation (the shape of Wine's committed range), then restoring the range.
- `cpu_probe`: a 200 ms busy thread, read through the sysctl census.
- `hid_probe`: the keyboard and mouse sysmodules opened; the user types and moves the mouse for 10 s.

| Step | What | Rule |
|---|---|---|
| g1n | `wow32.exe` on the native CPU: SEH of guest faults, x87/SSE2, a second thread | `PS4WINE g1n hello32 cpu=native native_caps=7 wow_bound=N/N seh=ok fp=ok thread=ok faults_unresolved=0 exit=0` (f1's rule on the native CPU). **On FAIL:** g's profile switches to `cpu=translator`, and the LOG line says why |
| g1m | `vk32.exe`: 32-bit placed maps, a GPU copy check | `PS4WINE g1m vk32 bits=32 map32=ok copy=ok faults_unresolved=0 exit=0` |
| g1 | `d3d9tri32.exe` under DXVK x32 d3d9, with the vampire profile's settings and batching, on g1n's CPU | `PS4WINE g1 d3d9 bits=32 map32=ok batch=1 frames>=300 gpu_hang=0 swapchain=1920x1080 fb=ok faults_unresolved=0` and `--fb` pixels from H4's host reference. Recorded: `crossings_per_frame`, the probe fields |
| g2 | Bloodlines to its main menu, from the profile: `Vampire.exe` relocated (`exe_base`), `Loader.dll` and its plugins, `ws2_32`, Bink, Miles | `PS4WINE g2 vtmb menu=1 faults_unresolved=0 exit=running`. `menu=1` is the user's first mark; an HDMI frame is kept as evidence |
| g | New game → character creation → first map; the second mark; 300 s | the rule above |
| gseg | Interior and hub segments | recorded; `check.sh gseg` checks that the fields are present |

| # | env.txt | Decides |
|---|---|---|
| L1 | `PS4WINE_MILESTONE=g1n` (the plan runs `C:\wow32.exe` with `WINE_PS5_WOW64_CPU=wow64native.dll`) | g1n: guest SEH on the native CPU, and with it g's CPU. `cpu_probe` runs here too |
| L2 | `PS4WINE_MILESTONE=g1m` (`C:\vk32.exe`) | g1m: placed maps |
| L3 | `PS4WINE_MILESTONE=g1` (`C:\d3d9tri32.exe`, `d3d9=n`, `DXVK_CONFIG_FILE=C:\g1\dxvk.conf`) | g1: 32-bit DXVK, batching, the profile's settings |
| L4 | `PS4WINE_MILESTONE=e` | the 64-bit regression after mesa-ps4 0003 |
| L5 | `PS4WINE_MILESTONE=g`, `WINEDEBUG=+loaddll` | the g2 line, then the g line, then an interior segment |
| L6 | `g` | load `g-hub` → hub segment; load `g-int` → interior segment |
| (L7) | `PS4WINE_MILESTONE=g1`, `PS4WINE_EXE=C:\dinput32.exe` (not built yet) | DirectInput 8 with the live keyboard and mouse; only if kbm failed in L5 |
| (L8) | `g`, `ORBIS_THREAD_FLOOR_KIB=1024` | **only if** `flex_mib_min` < 64 MiB in L5 or L6: RADV's thread stacks at 1 MiB, the size of Wine's kernel stack |

Iteration as in p: `build.sh wine --skip-host` and `runtime.sh --prx-only` for Wine-side fixes, no reinstall.
Plan g's watchdog limit is 7200 s, which h reuses.

## What gets built

The fork is `third_party/prospero-win` (LGPL); the repo is GPL.

**Gate path:**
- **mesa-ps4 `patches/mesa-ps4/0003` (repo): placed maps.**
  - `ac_drm_bo_cpu_map` with a requested address maps the BO's direct memory there as a CPU alias:
    phys = `orbis_arena_phys + (va - orbis_arena_map_base)` (`ac_orbis_drm.c:1123-1127`).
  - The unmap restores a reservation (`memoryUnmapReserve`).
  - `minPlacedMemoryMapAlignment` is 16 KiB.
- **Fork, Wine side:**
  - `link_prx ws2_32` in `build_wine_orbis.sh`;
  - `PW_VK_BATCH_STATS_EVERY=N` in `pw_vk_batch_pe.c` (default 1, so the PS5's behaviour is unchanged).
- **Fork, title:**
  - **Profile loading on Orbis:** `PS4WINE_PROFILE=vtmb` reads `/data/ps4-wine/profiles/vtmb.ini` through
    `src/pw_game_profile.c` and `src/pw_wine_launch.c`. It gives the exe, its arguments, the working directory
    (`pw_cwd_set`), the desktop, `d3d9=n`, the CPU, the input preset and the environment.
  - **Plans** `g1`, `g1n`, `g1m`, `g`, `gseg`: the marks, the window maths, `PW_VK_BATCH` parsing, `fps_avg`.
  - **Test programs:** `tests/wine_d3d9tri32.c`, and an i686 build of `wine_vk64.c`.
- **Repo:**
  - **`scripts/ps4/game.sh`:**
    - `lftp mirror -R --parallel=4` straight from `games/bloodlines-up` (`Vampire.exe`, `Loader.dll`, `Bin`,
      `Vampire`, `Unofficial_Patch`) to `/data/ps4-wine/prefix/drive_c/VTMB`;
    - a recursive remote listing, checked against every file's size;
    - a sha256 manifest in `build/`;
    - `--saves-push` and `--saves-pull`.
  - **`prefix.sh`:** DXVK `x32/d3d9.dll` into `syswow64`, the test programs, `C:\g1\dxvk.conf`.
  - **`runtime.sh`:** `ws2_32.prx`.
  - **`build.sh`:** `wine-desktop`.
  - **`check.sh`:** g1n, g1m, g1, g2, g, gseg, and the STAGES entries.

**Recorded only** (same package, no fix round before g):
- **mesa-ps4 `0004`:** the GPU busy sums, `ib_dw_max`, `heaps_mib`, and patch 0002's timer stopped before the
  shot.
- **orbis-compat `0002`:** `ORBIS_THREAD_FLOOR_KIB`, read from the module's own environ (the way `MESA_*` reaches
  libvulkan).
- **Fork ntdll:** the live/peak thread export, and the Orbis thread names.
- **Fork title:**
  - the sysctl census;
  - `native/orbis/pw_hid_orbis.c`, from `pw_hid_ps5.c` (KEY, MOUSE_MOVE, MOUSE_BUTTON, MOUSE_WHEEL through
    `pw_wine_post_input`);
  - the DS4 fallback `vtmb.input`;
  - `tests/wine_dinput32.c`.

## Not tested until the console says so (each LOG line names what it did not test)

- **Placed maps.** Unmeasured:
  - aliasing below 4 GiB, over Wine's own committed range;
  - 16 KiB placed alignment;
  - restoring the range on unmap.

  Aliasing and MAP_FIXED inside a reservation are measured (a, above 4 GiB, 2 MiB alignment).
- Guest SEH on the native CPU (g1n).
- `sysctl` thread runtimes on Orbis.
- `libSceKeyboard`/`libSceMouse` for an OpenOrbis title on this firmware.
- Batching on the PS4.
- 32-bit DXVK on GFX7.
- DXVK's deferred surface with our display hand-over.
- `memoryTrackTest` against RADV's arena-sized heaps.
- The `ws2_32` Unix side.
- `Vampire.exe` relocated, with the UP plugins.
- A large-address-aware guest sharing the low 4 GiB with placed maps.
- Bink; Miles through dsound on `wineps5`.
- DirectInput 8 on the user driver.
- Pipeline-compile stalls with GPL on GFX7.
- Bloodlines' frames against the 2 MiB submission cap.
- The one-in-1200 submit stall.

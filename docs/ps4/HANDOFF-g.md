# Hand-off: milestone g (Bloodlines, 32-bit D3D9 under WoW64 and DXVK 2.6.2)

Written 2026-11-01, after phase p (repo `fbd6853`). Read `CLAUDE.md`, then this, then `MILESTONES.md` (the g row
and note), `HANDOFF-p.md` ("Resume here") and `HANDOFF-f.md` ("Games on the host", the PE image table).

## Resume here (2026-11-01: plan approved, nothing built)

**Decided (the user, 2026-11-01):**
- **Desktop host Wine:** yes. The user installs the packages (H0); g builds a separate tree.
- **PS4 input:** USB keyboard and mouse, with a DS4 preset in the same build as the fallback.
- **g1 adds f1's `wow32.exe` on the native CPU** (g1n). If it fails, g runs on the translator and the LOG line
  says why.
- **The gate path comes first:** placed maps, `ws2_32`, arguments and working directory, Bloodlines to its menu,
  then g.
  - The recorded-only work ships in the same package but gets no fix round of its own before g: a failure records
    `-` and the work moves on.
  - The recorded-only work is the sysctl thread census, the GPU busy time and the `ORBIS_THREAD_FLOOR_KIB`
    launch.
  - That launch waits until g's `flex_mib_min` shows memory is tight (< 64 MiB, fixed now).
- **DXVK 2.6.2's built-in `vampire.exe` profile** was read before building (below); g1 runs under its settings.

**Done:**
- `build.sh wine` pins `--without-x --without-freetype` for the host trees. The string is the one these trees
  were configured with, so their stamps still match.
- This file.
- MILESTONES' g rule now has `gameplay=1`.

**Next:**
1. H0 (the user): the apt install below.
2. H1 onwards, gate path first.

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
| 1 | **32-bit Vulkan maps are refused.**<br>• RADV advertises `VK_EXT_map_memory_placed` (`radv_physical_device.c:955,1470`), so win32u's WoW64 path reserves a low range and asks for a placed map (`dlls/win32u/vulkan.c:507-520,1125-1176`).<br>• mesa-ps4's `ac_drm_bo_cpu_map` refuses any requested address ("cpu_map at a fixed address is not supported here", `ac_orbis_drm.c:7713`), and `has_userptr` is false on the PS4 (`ac_gpu_info.c:1116`).<br>• So 32-bit DXVK can map no host-visible memory. prospero-win's PS5 drivers map through a low CPU alias (fork `docs/WINE_PS5_BUILD.md:756-761,878`) | mesa-ps4 | yes |
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
| L1 | `PS4WINE_MILESTONE=g1`, `PS4WINE_EXE=C:\wow32.exe`, `WINE_PS5_WOW64_CPU=wow64native.dll` | g1n: guest SEH on the native CPU, and with it g's CPU. The title's probes run here too |
| L2 | `g1`, `PS4WINE_EXE=C:\vk32.exe` | g1m: placed maps |
| L3 | `g1`, `PS4WINE_EXE=C:\d3d9tri32.exe` | g1: 32-bit DXVK, batching, the profile's settings |
| L4 | `PS4WINE_MILESTONE=e` | the 64-bit regression after mesa-ps4 0003 |
| L5 | `PS4WINE_MILESTONE=g`, `WINEDEBUG=+loaddll` | the g2 line, then the g line, then an interior segment |
| L6 | `g` | load `g-hub` → hub segment; load `g-int` → interior segment |
| (L7) | `g1`, `PS4WINE_EXE=C:\dinput32.exe` | DirectInput 8 with the live keyboard and mouse; recorded only if kbm already worked in L5 |
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

# Milestones

Eight milestones, each with one scriptable check: `scripts/ps4/check.sh <letter>`
exits 0 (PASS) or 1 (FAIL) and prints the line that goes into `LOG.md`. The
check reads the title's machine-readable `PS4WINE <letter> key=value ...` line
from the log that `scripts/ps4/logs.sh` captured and, where a milestone says
so, one pixel from `scripts/ps4/shot.sh`. Screenshots beyond that are
evidence, not gates. Do not skip a milestone: each one tests what the next
relies on. The user launches the app; everything else is scripted.

Between f and g sits phase **p** (performance and audio, p1–p5, note below and
`docs/ps4/HANDOFF-p.md`). Its steps have their own lines and rules and gate
nothing unless a rule says so: only p2 feeds g, as g's choice of CPU.

Conventions for the `PS4WINE` line: `build=<sha7>[+dirty]` always; durations
in seconds (`session_s`), counts as integers, booleans as `0`/`1`. The line is
emitted by the title through klog **and** netlog so either source suffices.

| # | Milestone | Deliverables | Check (`check.sh <letter>` rule) | Main risk |
|---|---|---|---|---|
| a | Toolchain, hello-world PKG, probe | Host tools installed (clang/lld 18, cmake, ninja, meson, mingw-w64 i686+x86_64, glslang, python3, lftp optional); `refs/orbis-porting-kit` cloned (orbsdk is not public as of 2026-10-29); OpenOrbis v0.5.4 at `$OO_PS4_TOOLCHAIN`; orbis-compat and mesa-ps4 built; `probes/probe.c` (the ten questions in ARCHITECTURE §6) packaged with `pkg.sh`, deployed, installed, launched | Log line `PS4WINE a hello ok build=<id> direct_mib=<N> flex_mib=<N> reserve_gib=<N> jit=ok` with `direct_mib >= 4000` and `jit=ok`. The other probe fields (`sysarch=`, `frame_mc=`, `frame_fx=`, `frame_fs=`, `cs32=`, `loadexec=`, `dlsym=`, `cpus=`) are recorded, not gated | Header/ABI mismatches; wrong package layout (768 MiB) |
| b | Vulkan triangle via mesa-ps4 + capability dump | Title links `libvulkan_radeon.a` + vkloader, draws a triangle through `VK_EXT_headless_surface`, logs `apiVersion` and the extension list | `PS4WINE b triangle frames>=60 api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1` **and** `shot.sh --pixel 960,540 --expect-rgb 0,255,0 --tol 60` (triangle centre is pure green; background black) and `--pixel 240,135 --expect-rgb 255,128,0` (orange marker: swapped red and blue fail it, green alone cannot). Until the capture stick is in use, `check.sh b --fb` reads the same pixels from the title's framebuffer readback and logs `PASS (framebuffer)`, which does not discharge the HDMI pixel rule | A missing DXVK 2.6 requirement → fall back to DXVK 1.10.x |
| c | Wine core boots a 64-bit console EXE | Submodule `third_party/prospero-win` (fork, branch `orbis`); `build_wine_orbis.sh` produces `ntdll.prx`, `win32u.prx`, `wineserver.prx`; title loads ntdll, in-process server starts, `hello.exe` (PE64, prints to stdout) runs | `PS4WINE c hello.exe stdout="Hello from PE64" server=inprocess exit=0` | Signal frame, segment bases, umtx, paths, stacks (the a-probe answers decide the patch constants) |
| d | winemine / notepad (GDI) with DS4 | User driver + present sink + VideoOut linear path + pad input; a scripted click opens winemine's board; DS4 bindings move the pointer and click | `PS4WINE d winemine frames>=600 inputs>=10 refused=0 board_opened=1` (`board_opened` = the frame changed after the scripted click at a known cell, compared by the title) **and** `fb=ok` with d4's board pixels read from the title's framebuffer readback (`check.sh d --fb`; no capture stick). Sub-steps d1–d5 have their own lines, below | Display path, input delivery, fonts in the prefix |
| e | 64-bit D3D11 sample via DXVK 2.6.2 | `winevulkan.prx`, `libvulkan.prx`, win32u Vulkan driver on headless surfaces, display hand-over; a 64-bit D3D11 triangle (`d3d11tri64.exe`, ours: DXVK deleted its own d3d11 tests in 2022) presents through DXVK 2.6.2 | `PS4WINE e d3d11 frames>=300 gpu_hang=0 swapchain=1920x1080` **and** `shot.sh --pixel 960,540` within tolerance of the sample's triangle colour | Memory arena sizing, the 2 MiB submission cap, one-display WSI |
| f | 32-bit EXE via translator, then native probe | `wowprospero.dll/.prx`, prefix selects it; Space Cadet Pinball plays; `wow64native` readiness probe reports caps | `PS4WINE f pinball cpu=translator frames>=600 faults_unresolved=0 native_caps=<0..7>`. PASS needs the translator fields only; `native_caps=7` is recorded as a bonus | Executable memory above 4 GiB, SEGV hook, compat-mode selectors |
| g | Bloodlines (32-bit D3D9) with batching: gameplay reached | Profile + recipe for GOG's "Bloodlines - Unofficial Patch" (UP 11.5, standalone, extracted to `games/bloodlines-up`); prefix with the game on `/data`; `Vampire.exe -game Unofficial_Patch`; DXVK d3d9 under WoW64, `PW_VK_BATCH=1` + `PW_VK_BATCH_STATS=1`, RADV shader cache on `/data`, keyboard/mouse input; gameplay reached, batching on, 300 s | `PS4WINE g vtmb batch=1 crossings_per_frame<=2000 fps_avg>=20 session_s>=300 faults_unresolved=0` (Slim target; a Pro should reach 30) | CPU budget on Jaguar, shader-compile stalls; unmeasured: VirtualAlloc at fixed addresses, the large-address (2 GB RAM) fix, `Vampire.exe` relocated off the eboot's 0x400000 |
| h | Bloodlines: 30-minute session with save and load | On g's profile and prefix: new game → Santa Monica hub, save and load, 30-minute session | `PS4WINE h vtmb session_s>=1800 fps_avg>=20 faults_unresolved=0 saved=1 loaded=1` **and** a save file under `/data/ps4-wine/prefix/drive_c/.../Vampire/SAVE/` newer than the session start (checked over FTP by `check.sh`). The user confirms Santa Monica by eye; the LOG line notes it | Memory peaks at hub loads, HDD hitches |

## Per-milestone notes

**a.** The probe is one ELF with stages and timeouts (nx-on-orbis
`probe/probe.c` is the model; GPL, so it lives in `probes/`, never in the
fork). It writes `B:<stage>`/`E:<stage>` progress to
`/data/ps4-wine/probe/progress.txt` so a crashed stage is skipped on relaunch,
and shows a green/amber/red screen as a coarse signal for the capture stick.
Also deliver: `build.sh --check-toolchain` passes; `logs.sh` sees klog and
netlog; `shot.sh` finds the capture stick.

**b.** Use mesa-ps4's `build-support/orbis/tools/presentprobe.c` and
`tools/shaders/tri.{vert,frag}` as the starting point. Log `apiVersion`,
`deviceName`, the extension names DXVK 2.6.2 requires
(`maintenance5`, `robustness2`, `graphics_pipeline_library`,
`dynamic_rendering`, `transform_feedback`, `extended_dynamic_state3`,
`descriptor_indexing`, `timeline_semaphore`, `buffer_device_address`,
`custom_border_color`, `depth_clip_enable`), memory heap sizes and
`maxMemoryAllocationSize`. Keep `conditional_rendering` and
`draw_indirect_count` disabled in the driver (`patches/mesa-ps4/0001`). The
title (`probes/triangle.c`) also draws a 64x64 orange square centred on 240,135 and, at frame 300,
copies the presented swapchain image back and writes it to `/data/ps4-wine/shot.raw` (raw bytes in
VideoOut's A8B8G8R8 scan-out order, `fb=ok` in its line); `scripts/ps4/fbshot.sh` fetches and
converts it. That checks what the GPU rendered into the scan-out memory, not what leaves the HDMI port.

**c.** Everything in the a-probe that returned a value is a constant in the
fork: the signal frame and selectors in `wine/orbis/include` (0500/0501/0590
carry over unchanged), the direct-memory calls in `pw_wine_dmem_ps5.c`'s
`__ORBIS__` branch. First console run with Wine: expect to iterate on
`report.json` unresolved imports, raw syscalls in the shims and the in-process
server's `pipe()`/`fchdir` gaps, as prospero-win's bring-up log in
`WINE_PS5_BUILD.md` "Console bring-up" shows (runs 2–12). One build answers
several hypotheses at once, each as a `PW_WINE64` record: the PRX recipe
(`-pie --export-dynamic -e module_start` + `link.x`, no `crtlib.o`: `probe_mod`
loads, its constructor runs when `module_start` is called, `sceKernelDlsym`
sees its export), `pipe()` on this kernel, `dup2` onto fd 1/2, `sigaction` with
FreeBSD flags delivering to Wine's handlers with no alternate stack
(`sigaltstack` returned -1 in a), `socketpair` + `SCM_RIGHTS` for the in-process
server (`WINE_PS5_SERVER_DIRECT=0`, `WINE_PS5_MUTEX_SHARED=0`,
`WINE_PS5_SYNC_SHARED=0` on the first run: the stock paths only), the direct
memory self-check and the 16 GiB high area, the PE64 file mapping or its
`pread` fallback, and `STDOUT Hello from PE64` with `exit=0` through the exit
hook. The title emits exactly one `PS4WINE c` line (the hook's, the fault
handler's `exit=fault`, or the 180 s watchdog's `exit=timeout`); its other klog
lines carry no milestone letter. Runtime and prefix live on `/data`
(`runtime.sh`, `prefix.sh`), the package carries the title alone.
**Passed 2026-10-30 04:26, run 15** (`docs/ps4/LOG.md`, `docs/ps4/HANDOFF-c.md`).
What the fifteen runs taught, in order: the PRX recipe and page-aligned
segments; per-PRX musl state (`environ`, `stderr`, `exit`); no unix ownership
under `/data`; path `stat` without dev/ino; `dup` refused everywhere; the SDK's
`libc.a` ENOSYS stubs taken for real by configure (`epoll_create` put the
server's loop on `epoll_create()` = -1 for ten runs); `fcntl(F_SETFL,
O_NONBLOCK)` and `FIONBIO` refused on AF_UNIX sockets but fine on kernel pipes
(Wine's pipes are kernel pipes on Orbis now); musl's `getauxval` faulting on a
NULL aux vector; and a prefix that must keep its system32/syswow64 files.
Patches 1030/1040 (report and continue) and 1050/1060/1070 (handshake and
request traces, O_NONBLOCK tolerance) were diagnostic. They came out at the
start of d (2026-10-30), and only 1070's `init_thread` fallback stays
(`docs/ps4/HANDOFF-d.md`).

**d.** The host fixture `tests/wine_ps5_driver_sink.c` in prospero-win proves
the driver path on a PC first (winemine frames as PPM, scripted click; its
moves must be relative since patch 0670).
Fonts must be staged in `drive_c/windows/Fonts` on `/data`; `MenuHeight` must
not be in `user.reg` from a font-less wineboot (patch 0410). Five sub-steps,
riskiest first, each with its own `check.sh` rule (details and line formats in
`docs/ps4/HANDOFF-d.md`):

| Step | What | Rule |
|---|---|---|
| d1 | Cross-PRX binding: a two-PRX test (loader imports, data import, generated thunk table) and win32u.prx's 78 ntdll imports checked slot by slot; in the same launch, the title's linear VideoOut test pattern, the DS4 probe and `hello.exe` (c regression). Separate stages in that order (bind stages first), each result fsync'd to `/data/ps4-wine/d1/progress.txt` and logged before the next stage; a faulting stage is recovered or, after a crash, skipped on relaunch | `PS4WINE d1 bind=import\|thunk videoout=ok fb=ok hello=ok` and `--fb` 960,540 = 0,255,0, 240,135 = 255,128,0 |
| d2 | win32u inside Wine: user driver installed, offscreen GDI from `gdi64.exe`, frames reach the title's sink | `PS4WINE d2 gdi win32u=ok pixel=ff8000 exit=0` |
| d3 | FreeType (`libfreetype.prx`) and Wine's fonts in the prefix | `PS4WINE d3 fonts n>=1 tahoma=1 text_px>=50 exit=0` (`n>=13` was a guess, replaced before the first d3 run) |
| d4 | winemine on screen, scripted click opens the board | `PS4WINE d4 winemine frames>=2 board_opened=1 refused=0 fb=ok` and `--fb` 640,298 = 255,255,0, 634,390 = 0,0,0 from the host reference run (`frames>=600` replaced before the first d4 run: frames come on changes only) |
| d5 | DS4 drives pointer and buttons: milestone d's own line | the d rule above |

d1 passed 2026-10-30 14:45 (first launch); d2 and d3 passed 2026-10-30 15:29 (one launch, the fifth); d4 passed 2026-10-30 15:52 (second launch); d (d5) passed by its rule 2026-10-30 16:05 with input latency the user called far too high, and again at 16:10 after the present fix (8 ms average input to frame, "super smooth"). **Milestone d passed.** The d3 rule was settled before its first run as `n>=1 tahoma=1 text_px>=50 exit=0` (`HANDOFF-d.md`).

**e.** The title releases VideoOut when Wine creates its first surface. The
sample must present at 1920×1080 (the one size known to be accepted) before
trying scaled swapchains. Pixels come from RADV's own readback of the scan-out
(`patches/mesa-ps4/0002`, `ORBIS_WSI_SHOT`; `check.sh --fb`), since DXVK owns the
swapchain. Sub-steps, riskiest first (details and line formats in
`docs/ps4/HANDOFF-e.md`):

| Step | What | Rule |
|---|---|---|
| e1 | **Passed 2026-10-30 17:29.** `libvulkan.prx` (RADV with emulated TLS) opened through ntdll's dlopen and driven by the title: device and DXVK's features, the title's VideoOut closed, a 1920×1080 headless swapchain scanned out by RADV, a second swapchain (VideoOut reopened), then `hello.exe` beside the live device | `PS4WINE e1 vk vk_load=ok vk_bound=N/N inst=ok api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1 release=ok present=ok frames>=300 gpu_hang=0 swapchain=1920x1080 fb=ok hello=ok` and `--fb` 960,540 = 0,255,255, 240,135 = 255,128,0 |
| e2 | **Passed 2026-10-30 18:00.** `winevulkan.prx` (imports from ntdll and win32u) and win32u with Vulkan; `vk64.exe` creates an instance and a device under Wine | `PS4WINE e2 vk64 inst=ok api=1.3 exts_dxvk=ok dev=ok submit=ok wv_bound=N/N w32u_bound=N/N` |
| e3 | **Passed 2026-10-30 18:03.** win32u's surface on `VK_EXT_headless_surface` (patch 0461) with the hand-over through `pw_wine_release_display`; `vk64.exe` clears a Win32 swapchain (same launch as e2) | `PS4WINE e3 vkclear release=ok surface=ok present=ok frames>=300 gpu_hang=0 swapchain=1920x1080 fb=ok` and `--fb` 960,540 = 255,0,0, 240,135 = 0,255,0 |
| e4 | **Passed 2026-11-01 14:48 (HDMI and framebuffer).** `d3d11tri64.exe` under DXVK 2.6.2: milestone e's own line. One failed launch first (opengl32 without a unix library, fixed by patch 0480) | the e rule with 960,540 = 255,255,0 (`CHECK_E_RGB` default) and 240,135 = 0,0,255 from the host reference run |

e1 passed 2026-10-30 17:29 (second launch); e2 and e3 passed 2026-10-30 18:00/18:03 (one vk64.exe launch, the second); e4 passed 2026-11-01 14:48 (second launch). **Milestone e passed**, checked on both the framebuffer readback (`--fb`) and real HDMI: a frame from a recording of the whole launch through the capture stick (`check.sh e --shot`), the first HDMI pixel check of the project.

**f.** Pinball is prospero-win's case study (`docs/CASE_STUDY_PINBALL.md`).
Translator first; `native_caps` comes from a readiness probe that performs the
frame self-check and one guarded far jump, and refuses (caps 0) on any
mismatch. **Passed 2026-11-01 16:52** on the translator (54 presents/s, no
sound, `native_caps=-`). The readiness probe (f4) moved to p2, audio to p5.

**p.** Performance and audio, before g; details, line formats and the
threshold table in `docs/ps4/HANDOFF-p.md`. The benchmark is Space Cadet
Pinball in plan f with the pad bindings off: after a 20 s warm-up from
Pinball's first present, a fixed 60 s segment in attract mode with no input,
the same W and N every run, so runs compare like with like. Hand play after
the segment is recorded separately and never compared. fps is not a CPU
metric here (presents are vsync-locked, 54/s under a 60 Hz ceiling, and the
GDI driver presents only on change), so p compares per-flush times. p1's
instrumentation stays in every later build, so each step is re-measured on
the same segment. Each step gets its own `PS4WINE pN` line, a `check.sh` rule
and `tests/check_pN_test.sh` fixtures before its first run, and one LOG line
per launch. Thresholds T3, G and D are written into HANDOFF-p from measured
numbers before the step's first run and never moved after seeing its data.

| Step | What | Rule (`check.sh pN`) |
|---|---|---|
| p1 | **Passed 2026-11-01 18:06** (three launches, 18:00/18:03/18:06; HANDOFF-p has the numbers). Measure: per-flush histograms (min/avg/p95/max, integer µs) of guest time, copy (swizzle+scale), keep (the `last_drawn` copy) and flip wait; flushes per second and dirty area per flush. 3 launches of one package (run-to-run spread). No performance threshold | `PS4WINE p1 bench pinball cpu=translator seg_s=60 inputs=0 presents>=600 faults_unresolved=0` with every histogram field present |
| p2 | Native WoW64: f4's readiness probe (Orbis variant of 0883 as its own patch; first, `sigaltstack` via syscall 53 through libkernel's stub); with `native_caps=7`, the segment on `cpu=native`. Correctness only: guest time recorded, not gated | `PS4WINE p2 native native_caps=7 cpu=native seg_s=60 inputs=0 faults_unresolved=0 segment=done` |
| p3 | Drop the CPU copy: 960x540 A8R8G8B8_SRGB VideoOut buffers (no swizzle, no scale), if VideoOut scales them to 1080p (unmeasured); a 960x540 test pattern over HDMI first. GPU (RADV) only if it cannot | `PS4WINE p3 vo540 vo_register=ok vo_flip=ok seg_s=60 inputs=0 faults_unresolved=0 copy_us_avg<=T3` and HDMI 960,540 = 0,255,0, 240,135 = 255,128,0 |
| p4 | Non-blocking present: 3 buffers, submit the flip and return, wait only for a flip slot | `PS4WINE p4 async buffers=3 seg_s=60 inputs=0 faults_unresolved=0 shown_hz>=59 flip_errors=0` and p3's HDMI pattern check |
| p5 | Orbis audio on sceAudioOut (`pw_audio_orbis.c`, `wineorbis`, patch 0120's default), gated on Pinball's WAV effects in a scripted tail after the segment; MIDI music not tested | `PS4WINE p5 audio driver=orbis open=ok seg_s=60 inputs=0 faults_unresolved=0 grains_nonzero>=G underruns=0`, a rate gate (p4 passed: `shown_hz>=59`; p4 failed: `flush_hz` against the package's audio-off launch) and a non-silent HDMI audio track (peak >= D dBFS) in the `view.sh --record` recording |

**g.** Bloodlines from GOG's standalone "Bloodlines - Unofficial Patch"
(UP 11.5), extracted with innoextract to `games/bloodlines-up`
(`HANDOFF-f.md`, "Games on the host"), started as GOG's play task does:
`Vampire.exe -game Unofficial_Patch`. `Loader.exe` cannot run (it starts the
game by CreateProcess). Profile: `prefix = vtmb`, `[display] desktop =
1920x1080`, `dll_overrides = d3d9=n`, `[input] preset = kbm` (USB keyboard
and mouse), `[runtime] cpu = native` if p2 passed (its rule is correctness
only), else `translator`. "Gameplay reached": new game, character creation,
then the player in control in the first playable map, confirmed by the user by
eye and an HDMI frame. `PW_VK_BATCH_STATS=1` gives `crossings_per_frame`;
`fps_avg` comes from DXVK's HUD counter mirrored into the `alive` record. Keep
the RADV cache on `/data` between runs. Unmeasured risks, all for g's first
launches: what the game maps at fixed addresses at run time (VirtualAlloc with
a base); the large-address use of the 2 GB RAM fix; `Vampire.exe` wants
0x400000, inside the eboot's 0x400000-0x650000, and is relocatable (2052 bytes
of relocations, `HANDOFF-f.md` "PE images"), so Wine moves it as it moved
wow32.exe in f1, but whether anything (the UP loader's plugins included)
assumes the 0x400000 base is not known.

**h.** On g's profile and prefix. The 30-minute session (new game → Santa
Monica hub, save and load) is played by the user; `check.sh h` reads the
session log and the save file over FTP.

## Polish (not gating)

Work a milestone does not depend on. None of these blocks the next milestone; each is picked up
when the code it touches is next open, or before a build is handed to anyone else.

- **Clean app shutdown.** Closing the triangle from the PS menu gives CE-34878-0 (LOG.md "Known
  issues": two builds, kernel `gbase_gvmsw_close free_vm_space` error `0x804c0005`). The probe, idle
  with VideoOut open and the close request unhandled, closes cleanly, so the GPU side (RADV's arena,
  the GPU VM, queued flips) is the suspect, and releasing it is the part that matters. A title must
  handle the system's close request instead of being torn down in the middle of its present loop:
  find out how this firmware delivers that request to an OpenOrbis title (SystemService
  status/events; to be measured, not assumed), then stop presenting, `vkDeviceWaitIdle`, destroy the
  swapchain (which unregisters the VideoOut buffers and closes the port in `wsi_orbis.c`), the
  device and the instance, so RADV's arena and the GPU VM space are released before the process
  ends. Leaving must not itself be `exit()` or a return from `main()`: that is CE-34878-0 by
  definition (CLAUDE.md), so measure which exit the system accepts after a close request. Check:
  close the triangle from the PS menu, no CE-34878-0, and a `PS4WINE b close ok` line on klog.
  Applies to every title: the Wine title (from c on) owns a VideoOut port and later a Vulkan
  device too, and needs the same path (`pw_wine_release_display` is a natural place for it). **Not a
  blocker for c.**

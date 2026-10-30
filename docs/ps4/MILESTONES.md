# Milestones

Eight milestones, each with one scriptable check: `scripts/ps4/check.sh <letter>`
exits 0 (PASS) or 1 (FAIL) and prints the line that goes into `LOG.md`. The
check reads the title's machine-readable `PS4WINE <letter> key=value ...` line
from the log that `scripts/ps4/logs.sh` captured and, where a milestone says
so, one pixel from `scripts/ps4/shot.sh`. Screenshots beyond that are
evidence, not gates. Do not skip a milestone: each one tests what the next
relies on. The user launches the app; everything else is scripted.

Conventions for the `PS4WINE` line: `build=<sha7>[+dirty]` always; durations
in seconds (`session_s`), counts as integers, booleans as `0`/`1`. The line is
emitted by the title through klog **and** netlog so either source suffices.

| # | Milestone | Deliverables | Check (`check.sh <letter>` rule) | Main risk |
|---|---|---|---|---|
| a | Toolchain, hello-world PKG, probe | Host tools installed (clang/lld 18, cmake, ninja, meson, mingw-w64 i686+x86_64, glslang, python3, lftp optional); `refs/orbis-porting-kit` cloned (orbsdk is not public as of 2026-10-29); OpenOrbis v0.5.4 at `$OO_PS4_TOOLCHAIN`; orbis-compat and mesa-ps4 built; `probes/probe.c` (the ten questions in ARCHITECTURE §6) packaged with `pkg.sh`, deployed, installed, launched | Log line `PS4WINE a hello ok build=<id> direct_mib=<N> flex_mib=<N> reserve_gib=<N> jit=ok` with `direct_mib >= 4000` and `jit=ok`. The other probe fields (`sysarch=`, `frame_mc=`, `frame_fx=`, `frame_fs=`, `cs32=`, `loadexec=`, `dlsym=`, `cpus=`) are recorded, not gated | Header/ABI mismatches; wrong package layout (768 MiB) |
| b | Vulkan triangle via mesa-ps4 + capability dump | Title links `libvulkan_radeon.a` + vkloader, draws a triangle through `VK_EXT_headless_surface`, logs `apiVersion` and the extension list | `PS4WINE b triangle frames>=60 api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1` **and** `shot.sh --pixel 960,540 --expect-rgb 0,255,0 --tol 60` (triangle centre is pure green; background black) and `--pixel 240,135 --expect-rgb 255,128,0` (orange marker: swapped red and blue fail it, green alone cannot). Until the capture stick is in use, `check.sh b --fb` reads the same pixels from the title's framebuffer readback and logs `PASS (framebuffer)`, which does not discharge the HDMI pixel rule | A missing DXVK 2.6 requirement → fall back to DXVK 1.10.x |
| c | Wine core boots a 64-bit console EXE | Submodule `third_party/prospero-win` (fork, branch `orbis`); `build_wine_orbis.sh` produces `ntdll.prx`, `win32u.prx`, `wineserver.prx`; title loads ntdll, in-process server starts, `hello.exe` (PE64, prints to stdout) runs | `PS4WINE c hello.exe stdout="Hello from PE64" server=inprocess exit=0` | Signal frame, segment bases, umtx, paths, stacks (the a-probe answers decide the patch constants) |
| d | winemine / notepad (GDI) with DS4 | User driver + present sink + VideoOut linear path + pad input; a scripted click opens winemine's board; DS4 bindings move the pointer and click | `PS4WINE d winemine frames>=600 inputs>=10 refused=0 board_opened=1` (`board_opened` = the frame changed after the scripted click at a known cell, compared by the title) | Display path, input delivery, fonts in the prefix |
| e | 64-bit D3D11 sample via DXVK 2.6.2 | `winevulkan.prx`, `libvulkan.prx`, win32u Vulkan driver on headless surfaces, display hand-over; DXVK's `d3d11-triangle` (x64) presents | `PS4WINE e d3d11 frames>=300 gpu_hang=0 swapchain=1920x1080` **and** `shot.sh --pixel 960,540` within tolerance of the sample's triangle colour | Memory arena sizing, the 2 MiB submission cap, one-display WSI |
| f | 32-bit EXE via translator, then native probe | `wowprospero.dll/.prx`, prefix selects it; Space Cadet Pinball plays; `wow64native` readiness probe reports caps | `PS4WINE f pinball cpu=translator frames>=600 faults_unresolved=0 native_caps=<0..7>`. PASS needs the translator fields only; `native_caps=7` is recorded as a bonus | Executable memory above 4 GiB, SEGV hook, compat-mode selectors |
| g | 32-bit D3D9 Source game (HL2) with batching | DXVK d3d9 under WoW64, `PW_VK_BATCH=1` + `PW_VK_BATCH_STATS=1`, RADV shader cache on `/data`, keyboard/mouse input | `PS4WINE g hl2 batch=1 crossings_per_frame<=2000 fps_avg>=20 session_s>=300 faults_unresolved=0` (Slim target; a Pro should reach 30) | CPU budget on Jaguar, shader-compile stalls |
| h | Bloodlines (GOG + Unofficial Patch) | Profile + recipe for the GOG install with UP; prefix with the game on `/data`; new game → Santa Monica hub, save and load, 30-minute session | `PS4WINE h vtmb session_s>=1800 fps_avg>=20 faults_unresolved=0 saved=1 loaded=1` **and** a save file under `/data/ps4-wine/prefix/drive_c/.../Vampire/SAVE/` newer than the session start (checked over FTP by `check.sh`). The user confirms Santa Monica by eye; the LOG line notes it | Memory peaks at hub loads, HDD hitches, non-relocatable EXE (prospero-win #737) |

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
request traces, O_NONBLOCK tolerance) are diagnostic and come out at the start
of d, keeping only what a fix still needs.

**d.** The host fixture `tests/wine_ps5_driver_sink.c` in prospero-win proves
the driver path on a PC first (winemine frames as PPM, scripted click).
Fonts must be staged in `drive_c/windows/Fonts` on `/data`; `MenuHeight` must
not be in `user.reg` from a font-less wineboot (patch 0410).

**e.** The title releases VideoOut when Wine creates its first surface. The
sample must present at 1920×1080 (the one size known to be accepted) before
trying scaled swapchains.

**f.** Pinball is prospero-win's case study (`docs/CASE_STUDY_PINBALL.md`).
Translator first; `native_caps` comes from a readiness probe that performs the
frame self-check and one guarded far jump, and refuses (caps 0) on any
mismatch.

**g.** HL2 is the same engine family and the same input model as Bloodlines.
`PW_VK_BATCH_STATS=1` gives `crossings_per_frame`; `fps_avg` comes from
DXVK's HUD counter mirrored into the `alive` record. Keep the RADV cache on
`/data` between runs.

**h.** GOG build + UP 11.x (basic patch). Profile: `prefix = vtmb`,
`[display] desktop = 1920x1080`, `dll_overrides = d3d9=n`, `[input] preset =
kbm` (USB keyboard and mouse), `[runtime] cpu = translator` until f reports
`native_caps=7`. The 30-minute session is played by the user; `check.sh h`
reads the session log and the save file over FTP.

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

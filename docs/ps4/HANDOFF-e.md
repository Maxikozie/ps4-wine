# Hand-off: milestone e (64-bit D3D11 sample via DXVK 2.6.2)

Written 2026-10-30 16:15, at the end of the session that did milestone d. Read `CLAUDE.md`, then
this, then `MILESTONES.md` (the e row and its note), `HANDOFF-d.md` (how d was reached; every fact
below has its run there) and `LOG.md` (one line per console launch; d's are from 14:45 on).

## Where things stand

**Milestone d passed 2026-10-30 16:10**, after d1–d4 (`HANDOFF-d.md`):
```
PS4WINE d winemine frames=2257 inputs=2073 refused=0 board_opened=1 fb=ok ... lat_avg_ms=8 lat_max_ms=510 present_ms=15.0
```
- winemine runs under Wine on the PS4, with fonts.
- The user driver's frames reach the title's VideoOut.
- The DS4 drives the pointer through `pw_wine_post_input`. The user's verdict: "super smooth".
- Checked on the framebuffer readback only. The HDMI capture stick was never used.

**Nothing is committed.** The user commits. Uncommitted:
- **Fork** (`third_party/prospero-win`, branch `orbis`). New:
  - `tools/{orbis_import_stub,orbis_bind_table,gen_prx_imports}.py`, `tools/test_wine_ps5_driver.sh`;
  - `wine/orbis/{pw_wine_dl_orbis,pw_wine_dup_orbis}.c`;
  - `native/orbis/{pw_stage_orbis,pw_milestone_orbis,pw_videoout_orbis,pw_pad_orbis,pw_bind_*}.c`;
  - tests: `test_{orbis_prx_imports,gen_prx_imports,wine_gdi64,pw_stage_orbis,pw_wine_dup_orbis}`,
    `test_pw_wine_cwd_lexical`, `wine_gdi64.c`.

  Changed:
  - `tools/build_wine_orbis.sh`: sibling imports, FreeType, win32u and libfreetype with their own
    cwd emulation, `-soname`/`-libname`;
  - `tools/orbis_prx_report.py`: `sibling_imports`, `sce_imports`;
  - `tools/build_native_orbis.sh`, `wine/ps5/pw_wine_cwd_libc.c` (lexical `realpath`),
    `wine/orbis/pw_wine_compat_orbis.c` (`dup` by passing), `tests/wine_ps5_driver_sink.c`, the
    Makefile.
  - Patches 1030–1060 dropped, 1070 reduced.
- **Repo:** `scripts/ps4/{check,runtime,prefix,build}.sh`, `tests/check_d_test.sh` and the
  `d*-*.log` fixtures, the docs.
- **Host-only:** `.deps/wine-host-drv/` (a copy of the host Wine with win32u built
  `-DWINE_PS5_USER_DRIVER`, plus a `ps5drv_vulkan_cursor` stub). It is not in git.

**The console holds:**
- the d runtime PRXs (ntdll, wineserver, win32u, libfreetype, the bind test modules, and the
  `*.bind.txt` slot tables);
- the prefix with `gdi64.exe` and Wine's 13 fonts in `drive_c/windows/Fonts`;
- an empty `/data/ps4-wine/env.txt`;
- `ps4-wine-8659cda+dirty-lat.pkg` installed.

The newest title, with the pad loop starting at once after the click, is built in `build/title`
but not deployed.

**Host test state:**
- fork `PATH=/usr/lib/llvm-18/bin:$PATH make test`: exit 0, last run 15:51;
- repo `scripts/ps4/build.sh probe-test` and `tests/check_{a,b,c,d}_test.sh`: all pass.

## What d taught that e relies on (all measured; runs in LOG.md)

**PRX to PRX**
- One app PRX imports another's functions (and data) through the loader, bound at load, if:
  - the exporter is already loaded (the loader does not load a NEEDED app module itself);
  - the names agree: the exporter is linked `-soname NAME.so` and converted with
    `create-fself -libname=NAME`, and the importer is linked against a stub with that soname.
  `link_prx NAME TARGET OBJECTS EXPORTER` in `build_wine_orbis.sh` does all of it:
  1. a first link;
  2. `orbis_import_stub.py`;
  3. a stub `EXPORTER.so`;
  4. the real link;
  5. `orbis_bind_table.py` → `NAME.bind.txt`.
- **It takes ONE exporter.** winevulkan will need two, ntdll and win32u (Wine's winevulkan Unix
  side calls win32u's `__wine_get_vulkan_driver` and the like; check what it imports). Extend
  `link_prx`/`orbis_import_stub.py` to several exporters, with one stub each. NEEDED order matters
  to create-fself (see below), and the loader needs every exporter loaded before the importer.
- **create-fself's attribution.** It gives an import to the first NEEDED library exporting its name,
  and libkernel always comes first. libkernel exports `dlopen`/`dlsym`/`dlclose`/`dlerror`, which
  is why importers take ntdll's dlfcn as `__wrap_*` names.
- **The build checks:** `orbis_import_stub.py` refuses a name a NEEDED SDK stub also exports, and
  `orbis_prx_report.py` compares each OELF's per-library import counts (`sce_imports`) with the
  ELF's.
- **The title's check:** `w32u_bind`-style stages compare every GOT slot with
  `sceKernelDlsym(exporter, name)`, with `bound/zero/lazy/other` counts and `module+offset` for an
  odd slot. Reuse it for winevulkan and libvulkan.
- **TLS:** a PRX with PT_TLS loads (c). Importing a TLS variable from another PRX is untested, and
  the import stub refuses it. RADV and mesa have thread-locals of their own; keep them inside
  `libvulkan.prx`.

**libc and files**
- **`realpath()`** fails for every path with `libc.a` (musl + `readlink` stub). The cwd emulation's
  lexical one replaces it (`PW_CWD_LEXICAL_REALPATH`).
- **Virtual `dosdevices/c:`.** Every module that opens files by Wine's `dosdevices/c:` names needs
  its own cwd emulation, because the `c:` link exists only in its table. win32u and libfreetype
  have one, and `-u opendir` keeps libc.a's `opendir`. winevulkan probably needs none. RADV opens
  its shader cache on `/data` by real paths: fine.
- **`dup` is refused,** but `__wrap_dup` duplicates any descriptor by passing it to the process
  with SCM_RIGHTS (`wine/orbis/pw_wine_dup_orbis.c`). Modules linked without `--wrap=dup` (RADV,
  if it ever dups) get the real, refused one.
- **Private read-only `mmap`** of a `/data` file works. `O_NONBLOCK` works on kernel pipes, not
  on AF_UNIX sockets.

**Display and input**
- **The user driver** (patch 0400, built into win32u.prx):
  - an 800×600 desktop, BGRA frames to ntdll's present sink, only when something changes;
  - the title (`pw_ms_present`) integer-scales and centres them on its own two linear
    A8B8G8R8_SRGB buffers (scale 1 at 560,240);
  - the title must keep its per-frame work small: two 8 MB passes a frame made d's input "VERRYYY
    delayed".
- **One display.** The title owns VideoOut port 255 from its `display` stage on. In e, RADV's
  `wsi_orbis.c` must open VideoOut for DXVK's swapchain, so the title has to release it first:
  `pw_wine_set_display_release` / `pw_wine_release_display` exist in ntdll's sink for this; the
  PS5 title does it. After the release, GDI frames can no longer go to the title's buffers.
- **Input** goes through `pw_wine_post_input` (relative motion since patch 0670) and wakes GUI
  threads through `set_queue_fd`, which works since the `dup` fix.

**Tools and habits**
- **Milestone plans.** `native/orbis/pw_milestone_orbis.c` has plans `d1`, `d2`, `d4` and `d`,
  picked with `PS4WINE_MILESTONE=<plan>` in `env.txt` (the default is the newest). Each stage is
  recorded in `/data/ps4-wine/<plan>/progress.txt`. A relaunch resumes, and a stage lost in a crash
  or a close is not run again in that cycle. The Wine program is the last stage. Add plans `e1…`
  the same way.
- **Readback.** `/data/ps4-wine/shot.raw` (1920×1080 R,G,B,A) is fetched by `fbshot.sh` and checked
  by `check.sh <ms> --fb`. Other names: `fbshot.sh --remote /data/ps4-wine/<file>`.
- **netlog loses records under load.** The `GDI64` stdout line never arrived in d2's launches 4–5,
  while klog had the lines. Keep milestone lines on klog (`cfg.emit`), and keep `trace+file` off
  unless it is needed.
- **Give each new package its own file name**
  (`cp dist/ps4-wine-X.pkg dist/ps4-wine-X-<tag>.pkg`, then deploy that). The user once installed
  while the same name was being uploaded, and got a black screen.
- **Logs.** Start `logs.sh` before asking the user to launch. A session the user closes from the PS
  menu leaves no line, so keep per-second records in long stages.
- **Host driver Wine:** `tools/test_wine_ps5_driver.sh [--click X,Y] PROGRAM` runs a program under
  `.deps/wine-host-drv` with the sink fixture preloaded and dumps frames as PPM. It is headless,
  with no Vulkan and no FreeType, so it cannot run DXVK.

## Milestone e

**MILESTONES row:**
- **Deliverables:** `winevulkan.prx`, `libvulkan.prx`, win32u's Vulkan driver on headless
  surfaces, the display hand-over, DXVK's `d3d11-triangle` (x64) presenting.
- **Check:** `PS4WINE e d3d11 frames>=300 gpu_hang=0 swapchain=1920x1080`, and the triangle colour
  at 960,540. `CHECK_E_RGB` is to be fixed when the sample is chosen, before its first console run.

**Pins**
- DXVK 2.6.2 upstream: `https://github.com/doitsujin/dxvk/releases/download/v2.6.2/dxvk-2.6.2.tar.gz`,
  sha256 `17761876556afd55736cb895d184f5a1c55d43350f1b1e3b129f8d28706d7992` (the fork's
  `tools/pw_install.py` `DXVK_RELEASES`; 2.6.2-prospero1/2 are in the same table).
- The release has the DLLs, not the tests. `d3d11-triangle` comes from DXVK's source at tag
  `v2.6.2` (`tests/d3d11/test_d3d11_triangle.cpp`, meson with `build-win64.txt` and tests
  enabled), or the fork's own small PE in the style of `tests/wine_gdi64.c`.
- It compiles its shaders at run time (`D3DCompile`), so `d3dcompiler_47` (Wine's builtin) must be
  in the prefix. Check what the test imports.
- Pin the DXVK source the way FreeType is pinned (version, URL, sha256), with a `THIRD_PARTY.md`
  row.

**What already exists**
- **RADV:** `build/mesa-ps4/src/amd/vulkan/libvulkan_radeon.a` (mesa-ps4 `1a59cc1` + `patches/mesa-ps4/0001`).
  It is linked into the b title by `build.sh triangle`, and the b triangle presented through
  `wsi_orbis.c` (zero copy, A8B8G8R8_SRGB, 1920×1080, 59.9 fps).
- **The PS5's way to a PRX:** `tools/link_radv_prx.sh` and `wine/ps5/pw_vulkan_radv.c` in the
  fork (`vkGetInstanceProcAddr`/`vkGetDeviceProcAddr` exports, idle GDI show).
- **The Orbis plan:** ARCHITECTURE's `pw_vulkan_radv_orbis.c`: `libvulkan_radeon.a`
  `--whole-archive` + zlib + `-lSceGnmDriver -lSceVideoOut`.
- **winevulkan:** configured out today (`--without-vulkan` in `build_wine_orbis.sh`). The PS5 build
  shows the way: `ac_cv_lib_soname_vulkan=libvulkan.so`, `winevulkan_desc`,
  `link_prx winevulkan`, and `stage_vk_batch.py` already runs in the Orbis build.
- **Patches:**
  - 0450 (host-only `VK_KHR_display`) and 0460 (win32u's Vulkan driver on
    `vkCreateDisplayPlaneSurfaceKHR`, which releases VideoOut first) target the PS5;
  - on the PS4 the driver must create a `VK_EXT_headless_surface` instead (ARCHITECTURE "Vulkan");
  - 0455–0457 (scaling, placed map) carry over.

**Proposed sub-steps, riskiest first** (same scheme as d: each its own `PS4WINE eN` line, a
`check.sh eN` rule fixed before its first run, a plan in `pw_milestone_orbis.c`, several hypotheses
a launch):

1. **e1: `libvulkan.prx` alone.**
   - RADV linked as an app PRX: `--whole-archive`, its TLS, `-lSceGnmDriver`, size, the RADV
     arena in direct memory next to Wine's dmem (`ORBIS_ARENA_MIB`).
   - The title loads it, calls `vkCreateInstance` / `vkEnumeratePhysicalDevices`, and reports the
     device name, API version and DXVK's extension set (as b did).
   - Riskiest: nothing of RADV has run outside the title's own image yet.
2. **e2: `winevulkan.prx` and win32u with Vulkan.**
   - Configure with Vulkan.
   - Multi-exporter imports (ntdll + win32u, maybe libvulkan: winevulkan gets the driver by
     `dlopen("libvulkan.so")` through ntdll's dlfcn, so likely no loader import).
   - Slot checks in the title, as `w32u_bind`.
   - A tiny PE (`vk64.exe`: `vkCreateInstance`, enumerate, print) under Wine.
3. **e3: a surface and the display hand-over.**
   - Patch 0460 adapted to a headless surface.
   - The title's release of VideoOut (`pw_wine_set_display_release`), and RADV's `wsi_orbis` open.
   - A PE that creates a swapchain and clears it to a known colour for 300 frames.
   - The readback (next item) checks the colour.
4. **e4: DXVK's `d3d11-triangle`.** DXVK 2.6.2's `d3d11.dll`/`dxgi.dll` in the prefix as native
   overrides (`WINEDLLOVERRIDES` or the registry), at 1920×1080. This is milestone e's own line.
   - Watch the 2 MiB submission cap and `gpu_hang`; ARCHITECTURE §4.8 lists DXVK's traps.

**Open design questions to settle early**
- **The readback in e.** DXVK owns the swapchain, so the title cannot copy it as b did. Options:
  - a debug knob in mesa-ps4's `wsi_orbis.c` (a repo patch under `patches/mesa-ps4/`) that writes
    frame N of a swapchain to `/data/ps4-wine/shot.raw`;
  - or finally use the HDMI capture stick (`shot.sh`), which `check.sh e` uses by default.

  Decide before e3.
- **GDI after the hand-over.** The PS5 shows GDI through RADV's idle path
  (`pw_vulkan_radv.c` `pw_videoout_show_tiled`). For e it is enough that the triangle's window is
  the swapchain's. Say what is not shown.
- **One device at a time.** The b title opened RADV in its own image. Here only Wine's process
  does. The `display` stage of the plans must not open VideoOut when the plan hands it to RADV.

## Decisions (2026-10-30, after this hand-off was read)

- **No DXVK d3d11-triangle exists at v2.6.2.** DXVK deleted its d3d11 tests in August 2022 (commit
  `632e26f68`); the last `test_d3d11_triangle.cpp` was a 1024×600 grey line stress test with no
  frame count. Decided by the user: our own `d3d11tri64.exe` (fork `tests/wine_d3d11tri64.c`, C,
  mingw): a 1920×1080 window and swapchain, `D3DCompile` through Wine's builtin `d3dcompiler_47`, a
  yellow 255,255,0 triangle over a blue 0,0,255 clear, a staging readback printed with its line.
  It runs under DXVK 2.6.2's release DLLs (the pin in the fork's `tools/pw_install.py`); no DXVK
  source pin is needed.
- **Readback (decided by the user):** `patches/mesa-ps4/0002-orbis-wsi-shot.patch`.
  `ORBIS_WSI_SHOT=<n>` writes the process's n-th scan-out present, once, to `ORBIS_WSI_SHOT_PATH`
  (the title sets `<root>/shot.raw`) as R,G,B,A rows after the GPU wait, through `.tmp`, fsync and
  rename. `check.sh eN --fb` reads it: `PASS (framebuffer)`, the HDMI rule stays owed.
- **No native TLS in libvulkan.prx.** Measured on the host: `ntdll.shared.elf` has a PT_TLS segment
  and only `%fs:0`-relative local-exec accesses, no TLS dynamic relocation (lld relaxes a `-pie`
  image's TLS to local-exec, i.e. offsets into the eboot's block). RADV has 7 thread-locals in
  `.tbss.*` sections, which the SDK's `link.x` does not collect. So `build.sh mesa --prx` builds a
  second RADV (`build/mesa-ps4-prx`) with `-femulated-tls -march=btver2 -fno-omit-frame-pointer`
  (7 `__emutls_v.*`, no `.tbss`), and the fork's `wine/orbis/pw_emutls_orbis.c` (own code, host
  test `test_pw_emutls_orbis`) provides `__emutls_get_address`. Native PRX TLS is not measured.
- **libvulkan.prx** (`build_wine_orbis.sh`, module `libvulkan` when `PROSPERO_RADV_ARCHIVE` is set):
  RADV `--whole-archive` + zlib, `wine/orbis/pw_vulkan_radv_orbis.c` (`vkGetInstanceProcAddr`,
  `vkGetDeviceProcAddr`, a hidden `__dso_handle`, present/submit/swapchain counters exported as
  `pw_vulkan_stats`: the e lines take frames, the swapchain size and lost devices from there),
  `pw_wine_setenv` (ntdll's environment is replayed into it), ntdll as the one exporter (19 slots:
  exit/stdio/dl wraps, malloc family). 25 MB; `report.json` clean. `orbis_prx_report.py`'s raw
  syscall check now matches the mnemonic only: RADV's `callq <syscall>` (libc's ENOSYS stub, in a
  futex self-test) is not a raw system call.
- **Title.** `pw_videoout_orbis_close` closes port 255 and keeps the buffers' direct memory
  (nx-on-orbis: freeing it after the close rebooted the console). After the hand-over the GDI sink
  drops frames and counts them (`gdi_dropped`).

### e1: PASSED 2026-10-30 17:29 (second launch; LOG.md)

- **Launch 1 (CRASH)** found two bugs. RADV `strlen`ed `program_invocation_name`, which is NULL in
  a PRX: only crt startup sets musl's `__progname*`. `libvulkan.prx` now names the process in a
  constructor. The stage fault recovery then jumped to garbage, because the title's `sigsetjmp`
  was libkernel's (`libc.a` has none) and its `siglongjmp` musl's. The stages now use musl's
  `setjmp`/`longjmp`, and `build_native_orbis.sh` refuses a `sigsetjmp` import.
- **Launch 2 passed.** The title's VideoOut closed, then `wsi_orbis` opened port 255 from the PRX:
  zero copy, 330 frames at 59.2 fps, counted 330 by libvulkan's counters. A second swapchain
  reopened the port and presented 60 frames. `hello.exe` then ran beside the live device and the
  1024 MiB arena. The readback pixels are exact. The user saw cyan with an orange square.
- **The line was cut at 523 bytes by netlog's datagram size**, so `build=` and `stages=` were lost.
  It is now shortened to the gated fields plus `fps` and `reopen`; the stage records keep the rest.
- **Not tested by e1:** HDMI pixels, the Wine-first arena order, winevulkan, win32u's surface,
  DXVK.


Plan `e1` (the title's default, newest), stages in `native/orbis/pw_milestone_orbis.c` and
`native/orbis/pw_vk_stage_orbis.c`:

| # | Stage | What | Limit |
|---|---|---|---|
| 1 | `vk_load` | ntdll started and adopted as the Wine stage does, RADV's variables (`MESA_SHADER_CACHE_DIR=<root>/cache/radv`, `MESA_DISK_CACHE_DATABASE=1`, `ORBIS_WSI_SHOT=300`, `ORBIS_WSI_SHOT_PATH`, then `env.txt`) set in ntdll, a stage exit hook in ntdll; `libvulkan.prx` opened through ntdll's `dlopen("libvulkan.so")`; its 19 slots checked; flexible and direct memory before/after | 30 s |
| 2 | `vk_caps` | instance (`VK_KHR_surface`, `VK_EXT_headless_surface`, 1.3), first device, b's DXVK feature fields, heaps, max allocation, direct memory around the winsys' arena | 30 s |
| 3 | `display` | the title's VideoOut, as in d | 15 s |
| 4 | `release` | `pw_videoout_orbis_close` | 10 s |
| 5 | `vk_present` | device, headless surface, swapchain 1920×1080 FIFO (4 images, `R8G8B8A8_UNORM` if offered), 330 frames: clear cyan 0,255,255, a 64×64 orange 255,128,0 square on 240,135 copied in as bytes; fence or acquire later than 2 s = `gpu_hang`; then the swapchain destroyed and a second one presenting 60 frames (`reopen`: VideoOut closed and opened again, as DXVK's recreation does); the device stays | 60 s |
| 6 | `hello` | c regression, Wine starting beside RADV's live device and arena | 180 s |

Line:
```
PS4WINE e1 vk vk_load= vk_bound=N/N inst= api= device= maintenance5= robustness2= gpl= dyn_rendering= xfb= exts= heap0_mib= max_alloc_mib= display= release= present= frames= gpu_hang= swapchain= fmt= images= fps= fb= reopen= counted= hello= vk_first= load_ms= vk_kib= flex_before_mib= flex_after_mib= dmem_before_mib= dmem_after_mib= dmem_free_mib= flex_free_mib= device_lost= last_error= build= stages= stopped= launches= resumed= session_s=
```

Rule (`check.sh e1`, fixed before the first run; `tests/check_e_test.sh`): `vk_load=ok`, `vk_bound` all
bound, `inst=ok api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1 release=ok
present=ok frames>=300 gpu_hang=0 swapchain=1920x1080 fb=ok hello=ok`, and `--fb` 960,540 =
0,255,255 and 240,135 = 255,128,0. Recorded, not gated: `reopen`, `counted`, the memory fields.

### e2 + e3: e2 PASSED 2026-10-30 18:00, e3 PASSED 2026-10-30 18:03 (LOG.md)

- **Launch 1:** e2 passed. e3 did everything its rule asks (hand-over, 330 frames, exact pixels),
  but its counter fields read zero. The title's `module_handle("ntdll")` never matched, because
  the module list says `ntdll.prx`. The fallback path load fixed it, and `vk_stats=` now names any
  failed read. The rule is unchanged.
- **Launch 2:** both lines pass. win32u's surface creation (0461) asked for the display, the title
  closed VideoOut on its main thread, and RADV opened it zero copy from Wine's process.
  libvulkan's counters saw 330 presents at 1920×1080. The user saw red with the green square.
- **Correction to d1:** `module_named` now accepts `NAME.prx`. d1's `early_autoload=0` came from
  the same failing name comparison, so "the loader does not load a NEEDED app module by itself" is
  **unmeasured**, not measured. Load order stays the caller's job in practice.
- **Host tests.** The host Wine is built with Vulkan (`ac_cv_lib_soname_vulkan=libvulkan.so.1`).
  `.deps/wine-host-drv` was refreshed from it, with win32u rebuilt
  `-DWINE_PS5_USER_DRIVER -DWINE_PS5_HEADLESS_SURFACE`; no stub is needed now. Its prefix must be
  updated by the plain *build-tree* Wine: the update stamp is `wine.inf`'s mtime, and wineboot
  hangs under the driver. On lavapipe, `vk64.exe` passed both lines through 0461.


One launch of `C:\vk64.exe` (fork `tests/wine_vk64.c`, put by `prefix.sh --extras`) gives both lines,
as gdi64.exe gave d2 and d3. Plan `e2` (the title's default, newest):

| # | Stage | What | Limit |
|---|---|---|---|
| 1 | `w32u_bind` | win32u's ntdll slots: regression, win32u now has its Vulkan driver (97 slots) | 20 s |
| 2 | `wv_bind` | `winevulkan.prx`'s slots against **two** exporters: 14 from ntdll, 1 from win32u (`__wine_get_vulkan_driver`), each slot checked against its own exporter by the `.bind.txt` `from` column | 20 s |
| 3 | `display` | the title's VideoOut, so that the hand-over is real | 15 s |
| 4 | `vk64` | `vk64.exe` under Wine, 180 s watchdog | |

- **Build.**
  - Wine is configured with `ac_cv_lib_soname_vulkan=libvulkan.so` (no `--without-vulkan`), and
    `winevulkan.so` is built and linked by `link_prx winevulkan ... ntdll,win32u`.
  - `link_prx` and `orbis_import_stub.py` take several exporters in NEEDED priority order, one
    stub each, `--exporter NAME=ELF`. Host test: two-exporter cases in `test_orbis_prx_imports.py`.
  - Patch **0461**: under `__ORBIS__` (or `WINE_PS5_HEADLESS_SURFACE` on a host), the PS5 user
    driver maps `VK_KHR_win32_surface` to `VK_EXT_headless_surface` and creates a headless surface
    after `pw_wine_release_display`. 0460's display-plane path is unchanged on the PS5.
- **Title.**
  - `pw_wine_set_display_release(pw_ms_release_display)`: the port is closed on the title's main
    thread (`pw_ms_service` in the main loop, request and 5 s wait), as the PS5 title does.
  - The e plans add `MESA_SHADER_CACHE_DIR`, `MESA_DISK_CACHE_DATABASE=1`, `ORBIS_WSI_SHOT=300`,
    `ORBIS_WSI_SHOT_PATH` and `WINE_PS5_DESKTOP=1920x1080` to Wine's environment. libvulkan.prx
    gets them from ntdll when win32u loads it. `env.txt` wins.
  - The runner keeps the `VK64`/`VK64S` stdout lines (`pw_ms_stdout`).
  - `frames`, `swapchain` and `device_lost` come from libvulkan's `pw_vulkan_stats`, found through
    ntdll's `dlsym(NULL, ...)`. vk64.exe's own `frames`, `swapchain` and `hang` become `app_*`.
- **vk64.exe.**
  - **e2 half:** an instance with `VK_KHR_win32_surface` and the first device. It reports whether
    the DXVK set (swapchain, robustness2, transform_feedback, graphics_pipeline_library,
    extended_dynamic_state3, maintenance5) is visible through winevulkan, then creates a device and
    runs one empty submit with a fence.
  - **e3 half:** a 1920×1080 `WS_POPUP` window and its win32 surface, then a swapchain of its size,
    330 frames (RADV defers presents by one; the shot is the 300th). Each frame is a red clear with
    a 64×64 green square on 240,135 copied in as bytes.
  - Host test `test_wine_vk64.py`: the plain host Wine with Vulkan (`build.sh wine` passes
    `ac_cv_lib_soname_vulkan=libvulkan.so.1` when the host has it), on lavapipe, through the null
    driver's headless surface.

Lines:
```
PS4WINE e2 vk64 inst= api= exts_dxvk= dev= submit= wv_bound=N/N w32u_bound=N/N wv_driver= wv_first= exts= device= exit= build= ...
PS4WINE e3 vkclear release= surface= present= frames= gpu_hang= swapchain= fb= app_frames= app_swapchain= fmt= device_lost= gdi_dropped= display= exit= build= ...
```

Rules (fixed before the first run; `tests/check_e_test.sh`):
- **e2:** `inst=ok api=1.3 exts_dxvk=ok dev=ok submit=ok`, with `wv_bound` and `w32u_bound` all
  bound.
- **e3:** `release=ok surface=ok present=ok frames>=300 gpu_hang=0 swapchain=1920x1080 fb=ok`, and
  `--fb` 960,540 = 255,0,0 and 240,135 = 0,255,0.

## Open items carried from d (not blocking e)

- One input-latency spike of 510 ms in a 150 s session (otherwise ≤ 15 ms); cause unknown.
- The d title with the pad loop starting at once (no dead first seconds) is built, not run.
- In d4 the smiley in the last frame showed winemine's pressed face after a completed click.
- OPTIONS ending a session, the right button (circle), the HDMI output: untested.
- Polish from MILESTONES: a clean shutdown on the PS menu's close (CE-34878-0 risk once a Vulkan
  device is open).

## Iteration loop (as in d)

```
scripts/ps4/build.sh wine --skip-host        # Orbis PRXs; a patch or configure change reconfigures (~10 min)
scripts/ps4/runtime.sh --prx-only            # PRXs + *.bind.txt to /data (sizes verified)
scripts/ps4/build.sh title                   # when native/orbis changed
cp dist/ps4-wine-<id>.pkg dist/ps4-wine-<id>-<tag>.pkg && scripts/ps4/deploy.sh dist/ps4-wine-<id>-<tag>.pkg
scripts/ps4/prefix.sh --extras               # test programs + fonts into the prefix (put, not a mirror)
scripts/ps4/logs.sh --label eN --expect 'PS4WINE eN ' --timeout 7200 &   # before the user launches
scripts/ps4/check.sh eN --fb                 # then one line per launch in docs/ps4/LOG.md
```

Plan selection: `PS4WINE_MILESTONE=<plan>` in `/data/ps4-wine/env.txt`, next to `WINEDEBUG=...`
and the other knobs. Fork tests: `PATH=/usr/lib/llvm-18/bin:$PATH make test` in the fork, and read
the echoed exit line of a background run.

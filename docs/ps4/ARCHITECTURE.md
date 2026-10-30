# Architecture: prospero-win on the PS4

prospero-win runs Wine inside one PS5 title: Wine owns the Windows subsystem,
prospero-win owns IA-32 execution (the translator behind Wine's WoW64 layer)
and the platform boundary (video out, pad, audio, files, memory). The PS4 port
keeps that split. What changes is the platform boundary and everything that
was measured against the PS5 kernel. This document says, subsystem by
subsystem, what carries over, what is adapted, what is rewritten, and how the
pieces fit. Paths like `wine/ps5/pw_wine_dmem_ps5.c` are prospero-win paths
(`refs/prospero-win`, commit `0e7b6b4`); patch numbers are its
`wine/patches/NNNN-*.patch` series (101 patches on Wine `490f6d5d`).

## 1. The stack

```text
PE32 game (Bloodlines) + Wine i386 PE modules                   guest IA-32
  -> wowprospero.dll / .prx   prospero-win's x86 -> x86-64 translator   (milestone f)
     [later: wow64native.dll  hardware compatibility mode, if the Orbis GDT allows it]
     -> wow64 / wow64win thunks                                  Wine x86_64 PE modules
        -> ntdll.prx, win32u.prx, wineserver.prx                 Wine's Unix side, Orbis PRX
           built with OpenOrbis clang + orbis-compat overlay + prospero-win's wine/ps5 shims
           -> Orbis user driver (win32u, patch 0400 family), audio driver, xinput
              -> the title's sinks (frames, input, audio, pad)   native/orbis/*.c
                 -> sceVideoOut, scePad, sceAudioOut, sceKeyboard/Mouse, ImeDialog

PE64 program -> Wine x86_64 PE modules -> the same Unix side                (milestone c)

D3D8/9/10/11 (DXVK 2.6.2, PE, beside the game) -> winevulkan.dll
  -> [32-bit: PW_VK_BATCH queue, one crossing per ~25 calls]
  -> winevulkan.prx -> win32u.prx (Vulkan driver, patch 0460 adapted)
  -> libvulkan.prx = mesa-ps4 RADV (libvulkan_radeon.a, --whole-archive) + vkloader thunks
  -> ac_orbis_drm.c (no-DRM winsys) -> sceGnmDriver submit
  -> wsi_orbis.c: VK_EXT_headless_surface -> sceVideoOutRegisterBuffers + SubmitFlip
```

One title process per game, as on the PS5: the launcher restarts the title
with the game's arguments (`sceSystemServiceLoadExec`: works on the PS4, arguments
arrive from `argv[0]` on; see §4.1), so Wine always starts in a clean process and nothing has to
be torn down.

## 2. Repository layout

```text
ps4-wine/                       GPL-3.0 (this repo)
  CLAUDE.md, THIRD_PARTY.md, LICENSE
  docs/ps4/                     RESEARCH, ARCHITECTURE, MILESTONES, LOG
  scripts/ps4/                  build, pkg, deploy, logs, shot, check (bash)
  probes/                       first-week console probes (one ELF, stages with
                                timeouts, modelled on nx-on-orbis probe/probe.c)
  pkg/                          package skeleton: icon0.png, sfo values, right.sprx + sce_module from the SDK
  upstream/                     console-agnostic patches bound for prospero-win (LGPL, nx-free)
  patches/mesa-ps4/             our patches on mesa-ps4 1a59cc1, applied by build.sh mesa to its clone in build/
  third_party/prospero-win/     git submodule -> our fork of mpereiraesaa/prospero-win,
                                branch `orbis` (LGPL-2.1-or-later; created in milestone c)
  refs/                         read-only reference checkouts (gitignored)

third_party/prospero-win (the fork, branch `orbis`)
  native/orbis/                 the PS4 title: wine64_main_orbis.c (milestone c: load ntdll, run one
                                PE64, report; display, pad, audio come in d), orbislog/ (the ps5log
                                functions over UDP + klog), pw_probe_mod.c (the PRX recipe's check)
  wine/orbis/                   shims linked into the PRXs: pw_wine_exit_orbis.c (--wrap=exit,_exit,abort
                                → the title's hook), pw_wine_compat_orbis.c (thr_self, ppoll);
                                include/: FreeBSD-ABI headers over the SDK's musl ones (signal numbers and
                                flags, mcontext, selectors, traps, sockets, kevent, cdio, sysctl, mount)
  wine/ps5/pw_wine_dmem_ps5.c   the direct-memory glue is shared: `#ifdef __ORBIS__` picks
                                sceKernelAllocateDirectMemory over the one pool
  wine/patches/0100-0999        the console series, gates widened to `__PROSPERO__ || __ORBIS__` by
                                tools/widen_console_gates.py (0883 and 0903, native WoW64, stay PS5-only)
  wine/patches/1000-1499        Orbis-only patches under `__ORBIS__` (none needed for c so far)
  tools/orbis-clang             the CC wrapper (target, overlays, flags); build_wine_orbis.sh,
                                build_native_orbis.sh, orbis_prx_report.py, gen_prx_descriptor.py --orbis
```

Rule of thumb for where a file goes: if it links into `eboot.bin` or a Wine
PRX it lives in the fork (LGPL); if it is a host tool, a probe, packaging or
documentation it lives here (GPL). The title `eboot.bin` as shipped is GPL-3
anyway (OpenOrbis's `link.x`/crt are GPL-3), as prospero-win's is on the PS5.

## 3. What carries over

Legend: **as-is** builds unchanged (new target triple at most); **adapt**
keeps the design, changes constants or one platform call; **rewrite** is a new
file against a different API; **drop** has no PS4 counterpart.

### 3.1 Portable core (as-is)

| prospero-win | Role | Notes |
|---|---|---|
| `src/pw_x86_*.c`, `pw_x87.c`, `pw_guest_*.c`, `pw_vm*.c` | IA-32 translator | Pure C, imports only `stddef/stdint/string/limits`. Jaguar lacks nothing it needs (SSE4.2 is not advertised anyway). Slower on Jaguar; measured 85–93% of native on Zen 2 |
| `wine/wowprospero/` | Wine WoW64 CPU backend around the translator | Exec memory comes through Wine's VM (`place_above_guest()` → patch 0600 → direct memory + `sceKernelMprotect` RWX), so the Orbis dmem shim is the only dependency. Links the SDK's `emutls.o` for its `__thread` |
| `src/pw_game_profile.c`, `pw_app_profile.c`, `pw_profile_catalog.c`, `pw_wine_launch.c`, `pw_wine_start.c`, `pw_launcher_render.c`, `pw_present.c`, `pw_pad.c`, `pw_hid.c`, `pw_audio_mix.c`, `pw_tsc_calibrate.c` | Profiles, launcher, presentation math, input edge tracking, mixer | Platform-free |
| `wine/ps5/vulkan/*`, `pw_vk_*.c`, `tools/stage_vk_batch.py`, `generate_vk_codecs.py` | 32-bit Vulkan call batching (`PW_VK_BATCH=1`) | PE↔Unix only; mandatory on Jaguar where a guest→host crossing is dearer than the PS5's 2.8 µs |
| `wine/ps5/pw_wine_heap.c`, `pw_wine_heap_libc.c` | Wine's own heap (libc malloc caps at ~13 MiB on PS5; on PS4 it lives in the ~400 MiB flexible pool) | Backing goes to direct memory through the dmem shim |
| `wine/ps5/pw_wine_cwd*.c`, `pw_wine_compat*.c`, `pw_wine_threads*.c`, `pw_wine_sink.c`, `pw_wine_dl*.c`, `pw_ws2_32_libc.c` | Virtual cwd and symlinks, `pipe()` as socketpair, thread registry, title↔Wine sink, dlopen over `sceKernelLoadStartModule`, resolver | The same gaps exist on PS4 (no `fchdir`, relative paths refused, no `pipe` guaranteed). The resolver moves from `sceNetResolverStartNtoa` to PS4 libSceNet, same names |
| Wine patches 0100–0160 (fstab, realpath, registry writes, directory listing) | Unix services | Unconditional or `__PROSPERO__`-gated: widen the gate to `__ORBIS__` |
| 0110/0111/0770/0790/0810–0890 | In-process wineserver, client-thread sync requests, directory parking, change polling | Core of the design. 0770 matters even more on Jaguar (19–26 µs per pipe round trip on Zen 2) |
| 0400–0440, 0630–0671, 0879, 0902, 0965 | `dlls/win32u/ps5drv.c`: the in-process user driver (one virtual monitor, window composition into one frame, cursor blend, relative mouse) | Rename gate; the sink stays `pw_wine_present()` |
| 0470/0471 + `xinput1_3.so` unixlib | XInput from the title's pad sink | The title fills `XINPUT_GAMEPAD` from libScePad instead of the DualSense |
| `wine/wineps5/unix.c` | Audio driver: mixes to 256-frame 48 kHz grains and calls `pw_wine_audio_output` | Rename driver to `orbis`; patch 0120 defaults it |
| 0510, 0530, 0540, 0545, 0604, 0893, 0974 | 16 KiB host pages under 4 KiB Windows pages, USD page, fault counters, Windows-style stack commit, sub-page protection by single-stepping | The PS4 granule is also 16 KiB (`0x4000`) |
| 0550, 0896, 0971 | No process creation; exits leave through `exit()`; unhandled exceptions end the process | Same on PS4 (no fork/exec in a title) |
| 0611, 0614 | CPU backend chosen by env, fallback to the translator when the native CPU does not start | The "check, then fall back" design is kept |
| DXVK 2.6.2 (prospero-win's `v2.6.2-prospero2` fork) | D3D8–11 | Requirements met by mesa-ps4 RADV (§4.8) |

### 3.2 Adapted

| prospero-win | What changes on Orbis |
|---|---|
| `wine/ps5/pw_wine_prx.c` (PRXDESC1 export table scanned from `sceKernelGetModuleInfo` segments, because PS5 FW 12.02 `sceKernelDlsym` does not see app PRX exports) | As-is: the PS4's module info has the same layout, and the descriptor keeps the loader code host-tested. `sceKernelDlsym` does resolve app-PRX exports on the PS4 (milestone a), so the title logs it as a cross-check. The SDK's `crtlib.o` makes `module_start` hidden and never runs `.init_array` (milestone a `modstart=0`); `gen_prx_descriptor.py --orbis` emits a default-visibility `module_start` plus the module parameter block, so no crtlib.o is linked |
| `wine/ps5/pw_wine_dmem_ps5.c` (type `0x0c`, map `0x03`/`0xf2`, `sceKernelReserveVirtualRange` FIXED\|NO_OVERWRITE, 16 GiB then 512 GiB high area at `0x1000000000`, patches 0570/0600/0895/0897/0982) | `pw_wine_dmem_orbis.c`: `sceKernelAllocateDirectMemory(WB_ONION)` → `sceKernelMapDirectMemory` RW → `sceKernelMprotect` for EXEC (orbis-compat `src/orbis_jit.c` recipe, MIT). Reservation ceiling is 16 GiB (64 GiB fails `0x8002000c`), so `PW_PS5_HIGH_RESERVE_GB` starts at 8–16. Budget: ~4.4 GiB direct in total, RADV arena 1 GiB of it. `pw_wine_dmem.c` (policy, host-tested against a kernel model) is as-is |
| 0500/0501/0590/0903 (mcontext at ucontext+64, FXSAVE at +320, FS base at +1152, RIP +224; GS=TEB via `sysarch(131)`, FS restored via `sysarch(129)` on each Unix entry) | nx-on-orbis measured mcontext at +64 on PS4 too (rip +160, rsp +184, fault address +136 inside it, cs `0x43`, ss `0x3b`). **Measured in milestone a (LOG.md 2026-10-30): the PS4 frame equals the PS5's** (mc +64, rip +224, FXSAVE +320, FS base +1152, cs `0x43`, through both `sigaction` and `sceKernelInstallExceptionHandler`), and `sysarch` 128–131 get/set FS and GS. The 0500/0501 constants carry over unchanged |
| 0883 (`native_libkernel_resolver.c`: raw `sigaction` (syscall 416) through the `syscall` instruction at `getppid+10` inside libkernel, frame self-check with a marked MXCSR, `__wine_prospero_native_wow64_caps`) | Same stub shape is expected (FreeBSD-style `mov $N,%rax; mov %rcx,%r10; syscall`) but must be re-proven; PS4 numbers may differ. Also compare with `sceKernelInstallExceptionHandler`, which nx-on-orbis used for all faults. Keep the gate: caps stay 0 unless every check passes, and the translator runs |
| 0881/0882 (13 of 16 CPUs, SCHED_RR at priority 700) | Measured: the title's cpuset is `0x3f` (6 of 8 Jaguar cores at 1.59 GHz on the Slim; affinity to cores 6/7 is refused). Re-tune for 6. Affinity constants in `thread_budget.h` are per-thread arena sizes and stay |
| 0460 (win32u's Vulkan driver: win32 surface → `vkCreateDisplayPlaneSurfaceKHR`, title releases VideoOut first) | mesa-ps4 presents through `VK_EXT_headless_surface` (`wsi_orbis.c`), not `VK_KHR_display`. The driver creates a headless surface; patch 0450 (host-only `VK_KHR_display`) becomes a host-only `VK_EXT_headless_surface`. VideoOut has one display: the title still hands it over before the first swapchain (`pw_wine_release_display`) |
| `wine/ps5/pw_vulkan_radv.c` (`vkGetInstanceProcAddr` → `vk_icdGetInstanceProcAddr`, hardware cursor, idle/tiled GDI show) | `pw_vulkan_radv_orbis.c`: link `libvulkan_radeon.a` `--whole-archive` plus the kit's `vkloader.c`/`vkthunks.c` (771 weak thunks); no hardware cursor API known on PS4 (software cursor from patch 0420 suffices) |
| `native/pw_hid_ps5.c`, `pw_osk_ps5.c` (sysmodule IDs 0x0106/0x00a9, `sceKeyboard*`/`sceMouse*`, `sceImeDialog*`) | Same module IDs and record layouts as OpenOrbis documents; PS4 `OrbisImeDialogSetting` layout differs: adapt field by field |
| `tools/build_wine_ps5.sh`, `build_native.sh`, `link_radv_prx.sh`, `package_release.sh` | `build_wine_orbis.sh`, `build_native_orbis.sh`: CC is `tools/orbis-clang` (clang 18 at `x86_64-pc-freebsd12-elf`, `-isystem wine/orbis/include` then orbis-compat's overlay then the SDK, `-include orbis_prefix.h -D__ORBIS__ -D_BSD_SOURCE -march=btver2`; no `-femulated-tls`: Wine's Unix side has no `__thread` and the SDK ships no emutls runtime); Wine configures for `--host=x86_64-unknown-freebsd12` with every `linux/*.h` declared absent and `thr_kill2` declared present. PRX: `ld.lld -pie --export-dynamic -e module_start --script $OO/link.x` (an `ld.lld --shared` image crashes `create-fself`), the generated descriptor instead of `crtlib.o`, then `create-fself --lib`; the eboot links as the probe does. `tools/orbis_prx_report.py` writes `report.json` (unresolved, imports no SDK stub provides, data imports, raw syscalls) |
| `native/ps5log/` (TCP `ps5log/1` records, `dev.conf`) | `native/orbis/orbislog/`: same record names (`PW_WINE64 ...` lines, `TELEMETRY.md` contract), transport = UDP netlog to the host (orbis-compat `optional/orbis_netlog.cpp` scheme, 512-byte datagrams, port 18194) + klog (`sceKernelDebugOutText`) for the first lines and fatal records + `/data/ps4-wine/logs/session-N.log` (`pw_diagnostics.c` as-is) |

### 3.3 Rewritten

| prospero-win | Orbis replacement |
|---|---|
| `native/pw_videoout_ps5.c` + `pw_agc_ps5.c` (AGC DMA copy, tiled framebuffer, `sceVideoOutRegisterBuffers2`) | `native/orbis/pw_videoout_orbis.c`: two linear 1920×1080 `A8B8G8R8` buffers in direct memory, `sceVideoOutOpen/SetBufferAttribute/RegisterBuffers/SubmitFlip/WaitVblank`; the CPU copies the GDI frame (scaled by `src/pw_present.c`). There is no AGC; GPU blits, if ever needed, go through RADV |
| `native/pw_pad_ps5.c` (DualSense, trigger effects, `sceUserService` login list) | `pw_pad_orbis.c`: libScePad DS4 (`scePadInit/Open/ReadState/SetVibration/SetLightBar`), `sceUserServiceGetInitialUser` |
| `native/pw_audio_ps5.c` | `pw_audio_orbis.c`: `sceAudioOutInit/Open(MAIN, 48 kHz, S16 stereo, 256 frames)/Output`; same grain contract. nx-on-orbis proved the call sequence clean |
| `native/wine64_main.c` (1814 lines: launcher, LoadExec restart, data mount, frame/pad/audio loop, telemetry) | `native/orbis/wine64_main_orbis.c`: same structure minus the `/data` grant and Lapy; idle instead of returning from `main`; `sceSystemServiceLoadExec` restart if the PS4 allows it, else an in-process return to the launcher after Wine's `exit()` (needs a fresh process for the next game, so the fallback is "one game per launch, PS button to quit") |
| `sce_sys/param.json`, PS5 boilerplate crt, `ps5-native-tool` | `pkg/`: OpenOrbis `param.sfo` (CATEGORY `gd`, `SYSTEM_VER 0`), `sce_sys/about/right.sprx`, `sce_module/libc.prx` + `libSceFios2.prx`, paid `0x3800000000000011`, `link.x`/`orbis-tls.ld`, `create-fself --eboot`. This exact layout is what gives ~4.4 GiB direct memory on PS4 (nx-on-orbis measured the alternatives at 768 MiB or no boot) |
| `wine/ps5/pw_gnutls_libc.c`, `pw_vulkan_libc.c` (libc gaps of the PS5 payload SDK) | Gap list differs: `wmem*` on 16-bit `wchar_t` (orbis-compat `orbis_wchar32.c`), `__cxa_thread_atexit`, `strtof_l`. Start from orbis-compat's overlay and add what Wine's link report lists |

### 3.4 Dropped

| prospero-win | Why |
|---|---|
| `native/pw_data_mount.c`, `pw_lapy_elevation.c`, `lapy.elf`, elfldr 9021 | `/data` is writable for an OpenOrbis app under GoldHEN (nx-on-orbis: plain `mkdir("/data/...")` works). Note from playden: `/data` drops the sticky bit and root has no DAC bypass there |
| `third_party/mihawkgen`, `pw_framegen.cpp` | Frame generation needs GPU headroom the Slim lacks, and is GPL-3 inside the LGPL tree |
| `PS5_Vulkan`/ps5vk paths, `sceVideoOutCursor*` hardware cursor | PS4 uses mesa-ps4 only; software cursor |
| `tools/build_mesa_zink.sh` (OpenGL via Zink) | Not needed for D3D9. Zink works on mesa-ps4 (RPCS3 PS4 port), so it can return later |
| `PUBLICATION_ALLOWLIST.txt` audit | Replaced by the gitignore and the THIRD_PARTY rule; revisit before a public release |

## 4. Subsystems

### 4.1 Boot, packaging, process model
- `eboot.bin` is the title. It is an OpenOrbis ELF (PIE, `link.x` or the kit's `orbis-tls.ld`, `crt1.o`, `-lc -lkernel -lSceVideoOut -lScePad -lSceAudioOut -lSceUserService -lSceSystemService -lSceSysmodule -lSceNet -lSceGnmDriver`), converted by `create-fself`, packaged by `scripts/ps4/pkg.sh`, installed through GoldHEN from `/data/pkg`.
- The runtime (Wine PE modules, NLS, fonts, PRXs, DXVK) lives in `win/wine/lib/wine/{i386-windows,x86_64-windows,x86_64-unix}` + `share/wine/nls`. During bring-up it is uploaded to `/data/ps4-wine/runtime` over FTP (`scripts/ps4/runtime.sh`; the title looks there first, then under `/app0`), so a Wine fix is one PRX upload and no reinstall; shipping it inside the package at `/app0/win/...` needs `pkg.sh` to write its own gp4 (`create-gp4` takes every file in one argument). The mutable state is under `/data/ps4-wine/{prefix,profiles,logs,cache/radv}`; `env.txt` there adds NAME=VALUE pairs to Wine's environment. The prefix is initialised on the host (`scripts/ps4/prefix.sh`: `wineboot --init`; patch 0550 stops wineboot on the console) and uploaded once.
- `/app0` is read-only and cannot be listed (`opendir` fails on the PS5 image; expect the same): fonts and anything Wine enumerates are staged in the prefix on `/data`.
- One game per process: launcher → `LoadExec(eboot.bin, "profile=...")` → game → `exit()` → launcher (LoadExec with arguments works, milestone a). On the PS4 a title that calls `exit()` is reported as CE-34878-0, so the Wine PRXs are linked with `--wrap=exit,_exit,abort` (`wine/orbis/pw_wine_exit_orbis.c`): Wine's exit reaches a hook the title registered, which reports the run and, in milestone c, idles; the LoadExec restart to the launcher is the hook's later job.
- Packages are small (the title) plus the runtime (~500 MiB with both PE arches); Bloodlines (~4 GB) is uploaded once over FTP to the prefix.

### 4.2 libc, pthreads, TLS
- Compile everything against orbis-compat's overlay: `-isystem orbis-compat/include` before the SDK, `-include orbis_prefix.h`, link `liborbis-compat.a` (as a plain archive for the PRXs and the title: its boot member would install handlers of its own), `-lc++` for its C++ members, `-lc` last. It fixes `struct stat`, pthread attr sizes, 2 MiB thread stacks, `timer_create`, `clock_gettime`, relative paths, `umtx` over pthreads, `SA_*` and `sigaltstack`.
- The SDK's headers are musl's over a FreeBSD 9 kernel, and Wine's FreeBSD branch assumes FreeBSD's: `wine/orbis/include` sits ahead of both with the signal numbers (`SIGUSR1` is 30, not 10; `SIGBUS` 10), `SIG_BLOCK` 1, FreeBSD `mcontext_t` at the measured offsets, `machine/{trap,segments,sysarch}.h`, `sys/thr.h`, `sys/event.h`, socket structures with `sa_len` and a 12-byte `cmsghdr` (the in-process server's `SCM_RIGHTS` passing depends on it), `netinet/{in,tcp}.h`, `sys/{mount,cdio,sysctl,ioctl}.h`. musl's 128-byte `sigset_t` stays: its bit layout agrees with FreeBSD's for the first 64 signals.
- Wine's Unix side uses `__thread` only in wowprospero's `unix.c` (milestone f): then `-femulated-tls` plus an emutls runtime, which the OpenOrbis SDK does not ship (compiler-rt's `emutls.c`, Apache-2.0 with LLVM exception, from LLVM 18).
- Wine's `__wine_syscall_dispatcher` keeps FS = libc TLS and GS = TEB (patch 0500). Whether PS4 libkernel offers `sysarch(AMD64_SET_GSBASE)` decides between patch 0500 as-is and an LDT-free alternative (answered in milestone a: `sysarch(AMD64_SET_GSBASE)` works and `%gs:` loads then read through the new base, so patch 0500 stays as-is).

### 4.3 Memory
- Three pools: flexible (~384–440 MiB; libc malloc, anonymous mmap), direct (~4.4 GiB; everything large), GPU arena (direct memory the RADV winsys carves at startup, `ORBIS_ARENA_MIB`, default ladder 1024/512/256/128).
- Budget for Bloodlines (32-bit, 2 GiB address space unless LAA): guest + DXVK host-visible memory ≤ 2 GiB below 4 GiB, Wine heap + PE64 side ~300 MiB, translator arenas ≤ 256 MiB, RADV arena 1 GiB, GDI buffers 16 MiB, slack ~0.5 GiB. `PW_WINE64 memory` records (`dmem`, `dmem_low`, `heap_dmem`) show the real numbers every five seconds.
- Reservations: `sceKernelReserveVirtualRange` up to 16 GiB; the kernel's granule is 16 KiB; execute only via `sceKernelMprotect` after an RW map; mapping the same direct memory twice works; `sceKernelAvailableDirectMemorySize` returns the largest free block, not the total.
- Large pages: none used (prospero-win has no 2 MiB path either).

### 4.4 Signals, exceptions, SEH
- Wine needs real `sigaction` handlers with a `ucontext` it can edit (RIP/RSP rewrite, FP state). On PS4 nx-on-orbis got that through `sceKernelInstallExceptionHandler` (rewriting rip/rsp and returning resumes; ~4.9 µs per fault). OpenOrbis libkernel also exports `sigaction`. The probe tries both and records the frame layout (mcontext offset, FXSAVE offset, FS base offset, CS/SS values) once, with a marked MXCSR as 0883 does.
- Patch 0610's `__wine_ps5_set_segv_hook` (translator faults resumed inside Wine's SIGSEGV handler) and 0710 are kept.
- Never log or lock inside a handler (nx-on-orbis deadlocked its profiler that way); prospero-win's `fault` record is written raw for that reason.

### 4.5 32-bit execution
- **Phase 1 (milestone f):** `wowprospero.dll` + `wowprospero.prx`, selected by `HKLM\Software\Microsoft\Wow64\x86 = wowprospero.dll` and `WINE_PS5_WOW64_CPU`. Needs only RWX memory above 4 GiB and the SEGV hook.
- **Phase 2 (same milestone, informational):** `wow64native.dll` requires a 32-bit code selector. prospero-win uses CS32 `0x33`, SS `0x3b`, CS64 `0x43`, which are exactly stock FreeBSD amd64's GDT (`GUCODE32_SEL`, `GUDATA_SEL`, `GUCODE_SEL`). nx-on-orbis measured cs64 `0x43` and ss `0x3b` on the PS4, and milestone a's probe ran 32-bit code after a far jump to `0x33` below 4 GiB and came back through `0x43` (no fault). The milestone f readiness probe still performs its own guarded checks and reports `native_caps`; the game keeps running on the translator either way. No GoldHEN kernel patching to install selectors: that would be firmware-specific.
- Vulkan batching (`PW_VK_BATCH=1`) is on for both backends; `PW_VK_BATCH_STATS=1` logs crossings per present, the number milestone g gates on.

### 4.6 Threads and scheduling
- Wine threads come from `pthread_create` with 2 MiB stacks (overlay); Windows-sized commits via patch 0604. `__wine_main` runs on a 16 MiB-stack thread as in `src/pw_wine_start.c`.
- Reported CPU count = usable cores (patch 0881 with the PS4 affinity query). `thread_scheduling` (0882) is re-tuned once the Jaguar numbers are in.
- `pthread_kill` through the thread registry replaces `thr_kill2` (as on PS5).

### 4.7 Filesystem and paths
- `/data/ps4-wine/` root: `prefix/` (shared) or `prefixes/<name>/`, `profiles/*.profile` + `profiles.lst`, `input/*.input`, `logs/`, `cache/radv/` (`MESA_SHADER_CACHE_DIR`, `MESA_DISK_CACHE_DATABASE=1` because the PS4 cache index is anonymous memory).
- Absolute paths everywhere; the virtual cwd shim does the rest. `openat`/`mkdirat` only with `AT_FDCWD`.
- Over FTP, `.prx` files come back decrypted and large files can come back wrong: verify uploads by size (listing) and keep sha256 manifests on the host (`tools/pw_prefix.py` does this for prefixes).

### 4.8 Vulkan and RADV
- mesa-ps4 at `1a59cc1`: RADV on `CHIP_LIVERPOOL` (Slim/base, 18 CU) / `CHIP_GLADIUS` (Pro), GFX7, reports Vulkan 1.3 (measured 1.3.358, 197 extensions). Present in source: `KHR_maintenance5/6`, `KHR_robustness2`, `EXT_robustness2`, `KHR_dynamic_rendering`, `EXT_transform_feedback` (CTS had failures), `EXT_graphics_pipeline_library`, `EXT_extended_dynamic_state3`, `EXT_descriptor_indexing`, `KHR_timeline_semaphore`, `KHR_buffer_device_address`. Missing: float16, ASTC/ETC2, `external_memory_host`, `EXT_index_type_uint8`. DXVK 2.6.2's hard requirements are covered; milestone b dumps the real list.
- Build: `ps4/build.sh` with the kit's `orbis.ini.in` cross file; `-Dvulkan-drivers=amd -Dplatforms=orbis -Dllvm=disabled -Dshader-cache=enabled`. Driver defaults `ORBIS_3D_LINEAR=1`, `ORBIS_NO_TESS` (D3D9 needs no tessellation).
- Traps DXVK must respect: 2 MiB submission limit (watch DXVK's command buffer sizes; split submits if a game's frame overflows), no conditional rendering / draw-indirect-count (DXVK 2.6 uses the former for D3D11 predication only, d3d9 unaffected; disabled in the driver's extension and feature tables by `patches/mesa-ps4/0001`; nx-on-orbis avoided them in the consumer instead), ~1/1200 submit stall (pre-existing), `vkAllocateMemory` tops out around 896 MiB, surface formats RGBA only.
- Linking: `libvulkan_radeon.a` `--whole-archive` + zlib + `-lSceGnmDriver -lSceVideoOut` into `libvulkan.prx`, with `pw_vulkan_radv_orbis.c` exporting `vkGetInstanceProcAddr`/`vkGetDeviceProcAddr` as `pw_vulkan_radv.c` does; vkloader thunks only for the title's own Vulkan probe.

### 4.9 Display and WSI
- GDI/launcher frames: the title's own VideoOut (linear buffers, CPU scaled). Vulkan frames: RADV's `wsi_orbis.c` (zero-copy scan-out of the swapchain images when the format and size allow, else one GPU/CPU copy per frame). VideoOut accepts 1920×1080 (and 3840×2160 on PS5; the PS4 Slim list is to be measured); other swapchain sizes are scaled into a 1080p framebuffer as prospero-win does.
- One display, one swapchain at a time: the title closes its VideoOut before Wine's first surface (`pw_wine_release_display`), and GDI output after that goes through RADV's idle path (as `pw_vulkan_radv.c` does with `pw_videoout_show_tiled`).
- Red/blue: fixed in mesa-ps4 by offering RGBA formats only; DXVK's format list is honoured (patch 0456 keeps the chain).

### 4.10 Input
- DS4 via libScePad → `XINPUT_GAMEPAD` in the sink (xinput mode) and/or bindings to keys and the pointer stick (`.input` presets). USB keyboard and mouse via `sceKeyboard`/`sceMouse` sysmodules. Bloodlines wants mouse look + WASD: play with USB keyboard/mouse, DS4 as a fallback preset (`src/pw_script_input.c` macros for unattended runs).
- On-screen keyboard through PS4 ImeDialog for text fields (save names).

### 4.11 Audio
- `wineps5/unix.c` (renamed `wineorbis`) mixes to 256-frame 48 kHz S16 stereo grains; the title plays them with `sceAudioOutOutput` on the main port, the port is the clock.

### 4.12 Networking
- Low priority. `ws2_32.prx` with the resolver shim; no TLS build until a game needs it. Bloodlines is offline.

### 4.13 Logging and telemetry
- Three sinks, same records (`docs/TELEMETRY.md` in prospero-win): UDP netlog to the host (every record, never blocks), klog (`PS4WINE` startup lines, `fault`, `session_end`), and `/data/ps4-wine/logs/session-N.log` (eight newest, 1 MiB chunks, writer thread every 100 ms).
- Every milestone's title build prints one machine-readable `PS4WINE <letter> ...` line that `scripts/ps4/check.sh` gates on. The title's `build=` field is the fork's short commit plus `+dirty`, and the exact ELF is kept under `build/elf/` for `llvm-symbolizer` (crash records give `eboot+0x<rip-base>`).

## 5. Build pipeline

```text
host (Kubuntu)
  tools/build_host_wine.sh         Wine 490f6d5 --enable-archs=i386,x86_64 (mingw)   -> PE modules, winebuild, widl
  tools/build_wine_orbis.sh        patched Wine Unix side with OpenOrbis clang      -> ntdll/win32u/wineserver/
                                   + orbis-compat + wine/orbis shims, stage_vk_batch     winevulkan/xinput/... .prx,
                                   + FreeType, + link report                           pe/<arch>-windows for patched DLLs
  tools/build_wowprospero.sh       wowprospero.dll (host Wine tree)                  -> lib/wine/x86_64-windows
  tools/build_wow64native.sh       wow64native.dll (later)
  mesa-ps4 ps4/build.sh            RADV                                              -> libvulkan_radeon.a -> libvulkan.prx
  tools/build_native_orbis.sh      the title                                         -> eboot.elf -> eboot.bin
  scripts/ps4/pkg.sh               layout + param.sfo + gp4 + PkgTool                -> dist/<TITLE_ID>-<build>.pkg
  scripts/ps4/deploy.sh            FTP to /data/pkg (+ remote install)
console
  user: install (GoldHEN package installer) and launch
host
  scripts/ps4/logs.sh / check.sh / shot.sh -> one line in docs/ps4/LOG.md
```

Host checks come first: prospero-win's `make all` (73 C tests, ~91 Python
suites, publication audit) runs without a console, and the dmem policy, heap,
profile parser and translator all have host tests that cover the Orbis
constants once they are parameterised.

## 6. Open questions, answered by the milestone a probe

Each is one stage of `probes/probe.c` (crash-resumable, a timeout per stage,
result in the `PS4WINE a` line and in `logs/`):

1. Direct memory total and largest block with our package layout (expect ≥ 4000 MiB); flexible memory size.
2. Largest `sceKernelReserveVirtualRange` (expect 16 GiB); `MAP_FIXED` inside it; double mapping.
3. JIT recipe: direct → RW map → `sceKernelMprotect` RWX → execute a stub; RX narrowing.
4. `sysarch` availability for `AMD64_SET_FSBASE`/`SET_GSBASE` through libkernel; `rdfsbase/wrfsbase` from user mode.
5. `sigaction` with `SA_SIGINFO` vs `sceKernelInstallExceptionHandler`: frame layout (mcontext, FXSAVE, FS base offsets), CS/SS values, resume by rewriting RIP; the `getppid+10` syscall-stub shape in libkernel.
6. A guarded far jump to selector `0x33` (compatibility mode) and back.
7. `sceSystemServiceLoadExec` of our own eboot with arguments.
8. `sceKernelDlsym` on an application PRX export, and `module_start` execution.
9. Usable CPU count and clock (rdtsc vs `CLOCK_MONOTONIC`).
10. VideoOut: buffer sizes accepted, flip rate; audio port open/close.

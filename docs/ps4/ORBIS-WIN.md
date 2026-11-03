# orbis-win: what is worth porting

Written 2026-11-02, during milestone g (Bloodlines at its menu with sound; gc1 passed; gc2 and the USB mouse next).
This compares plastikman's `orbis-win` (`refs/orbis-win` at `2610706`) with our port (fork `third_party/prospero-win`,
branch `orbis`, `c76b600`). It is desk work only: nothing was built or run on the console.

**Their setup.**
- The console is a PS4 **Pro** on FW 9.60 (`docs/UPSTREAM-REPORT.md:3`).
- The gameplay packages default to base mode (`scripts/build-relocatable-wine-ps4.sh:23`, `NEO=0`), so RADV ran as
  Liverpool with 2 SE and 18 CU, as on our Slim. The Pro's CPU still runs at 2.13 GHz against our 1.6 GHz, so their
  frame rates are optimistic for us.
- Their flexible pool, about 440 MiB (`HANDOFF-2026-10-26.md:4483`), is the same as ours (431 MiB, `LOG.md:134`).
  Memory pressure therefore transfers one to one.
- prospero-win upstream `404cac6` (two commits before our pin `0e7b6b4`), plus `src/prospero-win-patches-ps4/0300`.
- Wine is built with `--patches src/wine-patches-ps4` (240 patches). This replaces prospero-win's own series. Their
  1009 is a whole-tree snapshot that also carries 14 upstream patches missing from their numbered series.
- Their platform layer is `src/native/*_ps4.c` and `src/freebsd-compat`.
- Mesa: mesa-ps4 `1a59cc1`, our pin, plus `src/mesa-patches-ps4` and `patches/`. DXVK 2.6.2 is app-local.

**Licence.**
- Everything is LGPL-2.1-or-later (`LICENSING.md`). The SPDX lines in the files agree. The only exception is
  `src/gfx-hang-probe/main.c`, which is MIT.
- A port into the fork takes `From: plastikman/orbis-win <path> @ 2610706 (LGPL-2.1-or-later)` and a row in
  `THIRD_PARTY.md`.
- **Not for the fork** (licence boundary):
  - Their Wine 0883 (`src/wine-patches-ps4/0883-*.patch:6,15,139`) and the copy in 1009 (`:3859`) cite nx-on-orbis as
    the rationale for a Sony exception-handler arm. That arm is compiled off (`0883:18`, `PW_PS4_FAULTS_VIA_SONY 0`),
    and the patch is upstream's older 0883 anyway.
  - `src/toolchain/prospero-clang:101` links orbis-compat's `orbis-tls.ld`.
  - `src/freebsd-compat/prx_module_param.ld:10` restates its KEEP rule.
  - `src/freebsd-compat/machine/fbsd_mcontext.h:54` cites nx-on-orbis for a fact only (mcontext at ucontext+64), which
    we already have.
  - No candidate ranked below is derived from nx-on-orbis or `orbis-tls.ld`.

**Evidence labels.**
- **code**: read in their source.
- **measured**: their docs quote a console log or a probe.
- **claimed**: stated without a log.
- **ours**: what our repository shows.

Their four games at gameplay are claims to us (see "Claims we cannot check").

Paths: theirs are relative to `refs/orbis-win/` unless they start with `refs/`. `S0300` is
`src/prospero-win-patches-ps4/0300-pre-mdk-source-snapshot.patch`. `WP/` is `src/wine-patches-ps4/`. `H10-09`,
`H10-14`, `H10-20` and `H10-26` are their `docs/HANDOFF-2026-10-*.md`. `F/` is our fork, `third_party/prospero-win/`.

## Top 5

1. **`sceGnmSubmitDone()` on every tick of the title's loop** ends the PS-button kill `0xa0d0c00a`
   (CPU_FAULT_SUBMITDONE_TIMEOUT_IN_SUSPEND_ASYNC). That is our open item 3 (`HANDOFF-g.md:145`; L10 at `LOG.md:135`).
   - Theirs: `S0300:114`, `:301`.
   - Measured: the suspend took 79 ms and the crash did not return (`H10-09:1909-1914`).
   - Title only, effort S.
2. **RADV worker threads on 4 MiB stacks instead of the 16 MiB floor**, through `--wrap=scePthreadCreate` on the
   libvulkan.prx link (`src/native/pw_vulkan_radv_ps4.c:238`, `:251`).
   - Gain: 72–108 MiB of the flexible pool, which fell to 152 MiB at character creation (`HANDOFF-g.md:172-174`).
   - A runtime change, effort S.
   - The user deferred a RADV stack knob (`HANDOFF-g.md:161`), so this needs their go-ahead.
3. **Left stick → WASD** (`keyboard_stick`). This frees the d-pad for `]`, TAB, h and F9 (`profiles/input/vtmb.input`).
   - Port upstream #736 as `HANDOFF-g.md:152` plans.
   - Check it against theirs (`S0300:75`, `:245`, `:283`, `:343`): a 5-count hysteresis, keys released before the
     opposite press, and held keys released when the pad stops reporting.
   - Title only, effort S–M.
4. **Measure DirectSound's timed wait before Bloodlines plays.**
   - On their console the mixer's `WaitForSingleObject(ev, 40)` returned after about 65 µs: about 15,000 passes a second
     instead of 25 (`H10-14:7476-7484`). That costs a core and floods `GetCurrentPadding`.
   - It was never root-caused. kqueue, server mode and a variant without `EVENTCALLBACK` did not cure it.
   - Bloodlines' Miles goes through dsound. Our L13 showed 2.42 cores busy and audio cutouts (`LOG.md:138`,
     `HANDOFF-g.md:148`).
   - Effort S to measure: their `src/wine-platform-patches-ps4/0006` counter, or an i386 test timing waits against QPC.
5. **Display-sized swapchain extents** (`WP/0861`).
   - win32u keeps the host surface's 1920x1080 instead of the window rect, so DXVK presents any game resolution into a
     scan-out-sized swapchain with its scaling blit.
   - This cures the 800x600 black menu (`HANDOFF-g.md:22`, `:155`) if ResPatch is ever lost. It also lets Bloodlines
     render below 1080p on 18 CUs.
   - Effort S, runtime.
   - The zero-code alternative is ResPatch 1280x720. A 720p buffer set registers (`HANDOFF-p.md:558-561`), but flipping
     one is untested.

## Ranked candidates

Ranked by value for milestone g first, then robustness. "Ours" names the equivalent, or says there is none.

| # | Candidate | Fixes | Theirs | Ours | Evidence | Effort | g / robustness |
|---|---|---|---|---|---|---|---|
| 1 | `sceGnmSubmitDone()` per loop tick (log rc once) | PS-button suspend kill `0xa0d0c00a` | `S0300:114`, `:301` (old `0026`) | None: the title loop `F/native/orbis/wine64_main_orbis.c:722-739` and the idle loops `:276`, `:324`, `:596`. mesa-ps4's opt-in `ORBIS_SUBMIT_DONE=1` only fires at a WSI present (`refs/mesa-ps4/src/vulkan/wsi/wsi_orbis.c:655-660`). The SDK declares it (`include/orbis/GnmDriver.h:252`). | measured (`H10-09:1909-1914`). Their `gfx-hang-probe/README.md:79-82` shows that a plain RADV probe gets the same kill, so it is not Wine's. | S, title | **high** / high |
| 2 | 4 MiB stack for RADV threads that ask for none or more | 16 MiB of flexible memory per RADV thread | `src/native/pw_vulkan_radv_ps4.c:225-270` | None. orbis-compat raises them to its floor (`HANDOFF-g.md:172-174`). The wrap fits beside our `--wrap=sceVideoOutOpen` (`F/tools/build_wine_orbis.sh:478-480`), below orbis-compat's `pthread_create` (`refs/orbis-compat/src/orbis_thread.cpp:288`). | measured: their GTA IV had 24×16 MiB regions and hit EAGAIN | S, runtime (g1m/g1/e again) | **high** / high. The user's go-ahead is needed (`HANDOFF-g.md:161`). |
| 3 | `keyboard_stick` / `stick_deadzone` | No stick can send keys | `S0300:75`, `:245`, `:283`, `:343` (old `0202`) | None. Upstream #736 is after our pin (`HANDOFF-g.md:152`). | measured (Oblivion's left stick, `H10-26:5135-5160`) | S–M, title | **high** (DS4 play) / med |
| 4 | dsound mixer wait counter (diagnostic) | Finds a busy mixer | `src/wine-platform-patches-ps4/0006` | None. p5 tested winmm only (`HANDOFF-p.md:195`, `:211`). | measured on theirs, cause unknown (`H10-14:7397-7523`, `:7750-7828`) | S | **med–high** if it reproduces |
| 5 | win32u keeps the host surface extents and clamps to `maxImageExtent` | Game resolutions VideoOut refuses | `WP/0861:64`, `:86` | None. Our WSI registers buffers at the swapchain's size (`refs/mesa-ps4/src/vulkan/wsi/wsi_orbis.c:331-336`), and 800x600 is refused. | code; their GTA swapchain `-3` fixed (`FINDINGS.md:3150-3164`) | S, runtime | **med** (performance lever, resolution safety) / med |
| 6 | Files the title writes on `/data` made 0666 (`fchmod`) | FTP 550 on title logs (`session-N.log`) | `src/native/pw_wow_log_ps4.c:60` | `F/native/pw_diagnostics.c:254-255` (`mkdir` 0700), `:266`, `:274` (0600) | claimed; matches our own FTP 550 | S, title | **med** (full logs when netlog drops half under `+vulkan`) |
| 7 | Diagnostics ready for the first gameplay hang or OOM: mesa 0003 (re-arm the hang dump, dump fence slots); `patches/0002`, `0004`–`0009` (RADV allocation and pipeline failure sites); DXVK `patches/0003`, `0010`, `0011` (VkResult of a descriptor pool; a null adapter or an image without storage throws `DxvkError` instead of segfaulting) | Unreadable first failure | as named | Ours has `dxvk_oom`, `heaps_mib` and `gpu_hang` fields (`HANDOFF-g.md:309`), no RADV failure sites | code | S each, runtime | **med** / med. Skip mesa 0033–0036 (they log every submit) and `patches/0007` (noisy). |
| 8 | NULL guard for threads without Wine `thread_data` | A debug line or exit on the in-process server thread or a foreign thread faults at 0x18/0x1c/0x7c | `WP/0749:55`, `:79`; the extra hunk in `WP/0882:105` | None: `.deps/wine-orbis/source/dlls/ntdll/unix/debug.c:71`, `env.c:2532`, `thread.c:1131-1140` | code; crash claimed | S, runtime | low–med / **med** |
| 9 | `SCHED_RR` must be 3 on Orbis | Priority calls get EINVAL | fact: `FINDINGS.md:1029-1061` (probe `src/present-test/main.c:380-400`) | `F/wine/patches/0882-*.patch:135` passes the SDK's `SCHED_RR` = 2 (`~/.local/opt/openorbis/include/sched.h:44`) through `F/wine/ps5/pw_wine_threads.c:52-59`. Harmless while `WINE_PS5_SCHED` is off. | measured | S | low now; needed before 0882's scheduling is turned on |
| 10 | Our own latent bug, found by comparison: the PS4's GPU protection bits are 0x33, not the PS5's 0xf2 | Fallback map with GPU bits | `src/native/pw_wine_dmem_glue_ps4.c:89`; SDK `include/orbis/_types/kernel.h:119-121` | `F/wine/ps5/pw_wine_dmem_ps5.c:57`, used at `:125` only when a CPU-only map is refused | code | S, runtime | low / low |
| 11 | mprotect trust-cache knob, failed-commit counters, and an RX re-apply when `sceKernelVirtualQuery` disagrees | Exec permission lost on a live page | `WP/1008:53`, `:87`, `:142`; `WP/0966:43`; `WP/0967:34` (skip the active stack in the force-exec walk) | None: `.deps/wine-orbis/source/dlls/ntdll/unix/virtual.c:218-231` skips silently. Our maps go through `counted_mprotect` (`virtual.c:305-307`) and `pw_wine_dmem_replace`, so their stated cause, their glue remapping behind the cache (`WP/1008:26`), probably does not occur here. | code | M (needs `sceKernelVirtualQuery` in ntdll.prx); 0967 S | low–med / med. Take the VirtualQuery check as a diagnostic first. |
| 12 | Heartbeat fields: `getrusage` minflt/majflt/inblock; the top flexible holders with their mapping counts | "Loading or stalled?"; the mapping-count limit (row F2) | `H10-14:6788-6795`; `H10-26:3470-3477`, `:5628-5631` | We log `flex_mib`, `dmem_peak_mib` and `threads_live`; no mapping count, no fault counts | measured | S, title | med / med |
| 13 | Round the `sceKernelReserveVirtualRange` size to a host page; refused reservation → VirtualQuery → `MAP_FIXED` | Non-relocatable EXEs whose size is not a 16 KiB multiple | `WP/1010:65`, `:94-151` | `.deps/wine-orbis/source/dlls/ntdll/unix/virtual.c:865` passes the size unrounded | code | S (rounding), M (the fallback is risky) | none (Vampire.exe relocates) / med |
| 14 | Wait watchdog reads the TEB and WoW64 CPU area through `ps5_peek` | Watchdog faults on a bad TEB | `WP/0920:57` | `F/wine/patches/0680-*.patch:185` dereferences directly | code | S | low / low–med (only with `WINE_PS5_WAIT_WATCHDOG`) |
| 15 | iretq frame with `cs32_sel`/`ss32_sel` instead of the context's CS/SS | `#GP` 0x20 when a guest context carries Windows' CS 0x23 | `S0300:4812`, `:4821` (old `0041`, which uses literals) | `F/wine/wow64native/cpu.c:450`, `:459` read the context | measured; where the 0x23 came from is unknown | S | low / low (games that build contexts themselves) |
| 16 | Relocatable title: a stub eboot, a high-address PRX, and the eboot released (`sceKernelMunmap` of every module-0 segment; their 0x400000–0x55c000 is a constant in their code, the measured stub was 0x400000–0x49c000, H10-26:5007-5010) just before the game starts. **Planned as milestone i (2026-11-02, `HANDOFF-i.md`)** | EXEs without relocations at 0x400000 (Oblivion, many pre-2008 games); see also upstream #737 | `src/reloc-wine-app/app_entry.c:55`, `:82`; `stub.c`; `S0300:126`, `:212` | None (`HANDOFF-f.md:55-58` names the risk) | measured (`H10-14:8-47`, `H10-26:5002-5035`; `FINDINGS.md:2379-2395`, `lowbase-probe/README.md:9-20`) | **L**: all title code moves into a PRX | none (Vampire.exe relocates to 0x00110000) / **high** for 32-bit games in general |
| 17 | Loopback or NetCtl adapter for `GetAdaptersAddresses`; `gethostbyname` through a title shim | Titan Quest's garbage read after error 2 | `WP/0979:73`, `WP/0989:80`, `WP/0988:28`; `src/native/pw_netctl_ps4.c` | None. Our resolver is the SDK libc's (`F/tools/build_wine_orbis.sh:451-456`). `gethostname` returns "" (`H10-20:2568`). | measured (`H10-20:2922-3170`) | S (0979, PE side); M–L (0988/0989) | low (Bloodlines' net init passes) / med |
| 18 | ImeDialog on-screen keyboard | Text entry without a keyboard (save names) | `src/native/pw_osk_ps4.c` | None for the PS4 (`F/native/pw_osk_ps5.c`) | measured (`H10-26:4474-4481`) | M, title | low (the USB keyboard works) / med |
| 19 | CPU cursor composite into the scan-out buffer | A cursor over Vulkan frames | `patches/0012-radv-wsi-cursor-composite.patch:87`, `:142`; same `pw_videoout_cursor` signature (`src/native/pw_vulkan_radv_ps4.c:29`) | Ours uses VideoOut's hardware plane (gc1 PASS, `HANDOFF-g.md:110-118`) and costs nothing per frame | code | S, runtime | fallback only, if gc2 fails |
| 20 | A zero-timeout MsgWait returns after one stale wake | DirectInput spin | `WP/0907:21` | Our 0879 fixes the root cause (`F/wine/patches/0879-*.patch:58`) | claimed | S | port only if a spin is measured |
| 21 | `NtQueryDirectoryFile` through a getdents scanner | Empty save list (Oblivion) | `WP/0908:27`, `:71` | musl `readdir` lists `/data` (`F/wine/ps5/pw_wine_cwd_libc.c:678-689`; f2 `fonts=9`, `LOG.md:92`). Their failure was Sony's libc (`FINDINGS.md:2550-2571`). | measured on theirs | M | only if Bloodlines' Load menu comes up empty |

## Do not port

| Theirs | Why not |
|---|---|
| Descriptors handed over by number, borrowed or shared: `WP/0734`–`0738`, `0745`, `0866`, `0869`, `0871`, `0972`; `__wrap_dup` → `sceKernelRdup` (`S0300` around `:4069-4100`) | It rests on "no descriptor can be duplicated". Their dup-probe never tried SCM_RIGHTS, and `sceKernelRdup` is EPERM by their own table (`FINDINGS.md:2277-2291`). We get real duplicates (`F/wine/orbis/pw_wine_dup_orbis.c:26`). Taking their model would be a regression. |
| "Nonblocking is impossible": `WP/0742`, `0771`, the poll arm of `0903` | Kernel pipes take `O_NONBLOCK` (`LOG.md:69-70`); `F/wine/patches/1070` covers socket pairs. |
| `WP/0743`, `0744`, `0746`, `0747` (null environ, USD length, wineboot, getauxval) | Covered by `F/wine/orbis/pw_wine_env_orbis.c` and the getauxval shim (`pw_wine_compat_orbis.c:280`). |
| `WP/0883` (theirs) | Upstream's older resolver, fingerprinted to one PS5 libkernel, plus a disabled Sony arm whose rationale is nx-on-orbis. Ours is upstream's newer one plus `1090`. |
| `WP/0910`, `0930`, `0934`–`0946` (SIGSYS routing, single-step consumption, privileged instructions) | Our raw-sigaction entry (`1090`) passed g1n without them. 0945 itself retracts 0940–0944's premise. SIGSYS cannot be caught anyway (`FINDINGS.md:2122-2123`). |
| `WP/0954`–`0956` (RX repair at hard-coded Oblivion addresses) | Game-specific. Row 11 is the general form. |
| Exec-page migration to flexible memory: `src/native/pw_wine_dmem_glue_ps4.c:461`, `:638`, and its follow-ups `0083` and snapshot Wine 1000 (`S0300:3267`) | Unlocked unmap and remap. It hit the mapping-count limit (row F2) and caused not-present faults. |
| Low TCB pool, FiberData = page + 0x1e00 (`S0300:5752`, `:6435`; old `0035`/`0071`) | Needed only for handlers registered through libkernel's trampoline. Ours take the raw syscall, and it breaks fibres. |
| `WP/0960` (kqueue because epoll is stubbed) | We declare epoll absent, so the server already uses kqueue (`F/tools/build_wine_orbis.sh:156`, `:165-168`). |
| `WP/0861`'s and `0862`'s hard 1920x1080 pin | Take only the host-extents idea (row 5). |
| `WP/0860`, `0879` (DXGI composition swapchain, dcomp) | GTA IV's 1911.dll path; D3D9 on DXVK does not use it. |
| `WP/0660`–`0662`, `0720`–`0723` (PS5 EGL/OpenGL) | Upstream removed it, and the PS4 has no such SDK. |
| Wine-side translator changes: 0015 (8 MiB flexible arenas, `S0300:7431`), 0017 (`:7673`), the `pw_x86_hostexec` rewrite (`:753`, `:903`) | Ours are ahead: translator memory is lazily committed direct memory, one malloc for every PRX through ntdll, upstream's more general segment forms. |
| `src/native/pw_emutls_ps4.c:61` | One pthread key per variable runs out with RADV; ours uses one per process (`F/wine/orbis/pw_emutls_orbis.c:92`). |
| `src/wine-platform-patches-ps4/0004` (drop `EVENTCALLBACK`) | Falsified by their own A/B. |
| Mesa 0007 (500 ms fence slot) | **Harmful**: a stall that would recover becomes a lost submit (`-ETIME`, `refs/mesa-ps4/src/amd/common/ac_orbis_drm.c:9855-9857`). |
| Mesa 0001 (= `patches/0001`), 0004, 0014, 0020 | Pro (Neo) only. They do nothing in base mode or on a Slim. |
| Mesa 0002 (placed CPU alias) | We have it, more complete (`patches/mesa-ps4/0003`). Their unmap order is hardware-proven, though: see row F7. |
| `src/toolchain/prospero-clang:101`, `src/freebsd-compat/prx_module_param.ld` | `orbis-tls.ld`; licence boundary. Not needed with our `link.x`/`module_start` recipe. |
| DXVK settings: `numCompilerThreads=1`, GPL off, `d3d9.maxAvailableMemory=256` (`src/gtaiv-config`, `falloutnv-config`, `titan-quest-config`) | None helped in their A/Bs (`H10-20:73-80`, `:4097-4105`; `H10-14:6749-6768`; `H10-26:3497-3522`). `numCompilerThreads=0` stalled startup (`H10-20:5918-5937`). Keep DXVK's `vampire.exe` profile. |

## PS4 facts they measured that we have not

Facts need no licence. "Pro?" marks facts that may not hold on a Slim.

| # | Fact | Where | How measured | Pro? | Why it matters for g |
|---|---|---|---|---|---|
| F1 | Running out of flexible memory during a load shows as RADV host OOM, not a crash: DXVK logs `Exception on CS thread`, `VK_ERROR_OUT_OF_HOST_MEMORY` on end command buffer, a descriptor pool failing at `maxSets=24576`, or `RADV_GRAPHICS_PIPELINE_FAIL stage=stage_array_alloc`. Presents stop while audio continues. | `H10-20:51-97`, `:185-254`; `H10-26:3014-3062` | logs | no | This is how a level load will fail at 152 MiB free. The fix was routing the Unix heap to direct memory (`H10-26:3246-3388`). Ours already is (`LOG.md:59`: "heap in direct memory"). |
| F2 | A per-process **mapping-count limit**: `mmap` returned EINVAL with about 63 MiB of flexible memory free, once one holder had about 4,767 mappings. Pages Wine thinks are committed are then absent: guest `err=0x4` faults at a reproducible depth. | `H10-26:4219-4251`, `:4327-4385` | logs | no | Our exposure is unknown: we log no mapping count (row 12). |
| F3 | `sceKernelMprotect` to RX on direct memory returned 0, but `sceKernelVirtualQuery` still showed no exec. Pages also went from RX to R with no protection call. | `H10-14:6037-6060`, `:6226-6239`; `H10-26:5319-5332` | logs, one page | no | **Explained on our Slim (2026-11-03, LOG L19, L23-L28).** The first half is the query's encoding: direct memory RX reads 1, RWX 3 (L19), so "no exec" in the query is no evidence. The second half is the kernel's module loader: on every module load (app PRX or sysmodule) it re-protects module 0's `PT_SCE_RELRO`, read-write during the load and read-only after, even after the eboot was released, over whatever is mapped there, on direct and flexible memory alike (L23). Their fault pages 0x4a4000-0x4ac000 lie in their eboot's former data area (0x49c000+, FINDINGS.md:789-791, H10-14:32-34); their RELRO's exact range is not in refs. Our fix is a stub without `PT_SCE_RELRO` (`F/tools/pw_stub_orbis.ld`, `F/tools/orbis_stub_norelro.py`, HANDOFF-i.md "The cause and the fix"); no repair is needed (L27, L28). |
| F4 | What a GPU hang looks like: `VK_ERROR_DEVICE_LOST`; the HP3D watchdog kills Shell UI about 3 s later and the title about 4 s later, so any diagnostic wait over about 1 s is never logged; the system runs `gpudump.elf`; after 45 s comes `0xa0d0c007`; RADV's MMIO hang-register reads are refused. | `FINDINGS.md:3799-3811`, `:4065-4076`, `:4151-4152`; `H10-09:377-395`; `src/gfx-hang-probe/README.md:102-104` | klog, radv.log | no | Plan the capture for the first gameplay hang ahead of time (row 7). |
| F5 | Four-submission stalls recover; the fatal hang is a separate event. | `FINDINGS.md:3880-3893`, `:4173-4176` | radv.log | no | Matches our "1 submit in 1200 stalls". Do not shorten waits (mesa 0007). |
| F6 | `.sorbisdmp` crash dumps are encrypted (entropy 7.9994). GoldHEN announces the coredump path in klog (`coredump.path,name,mode={…}`) and deletes the dump about 20 s later. | `AGENTS.md:10-22`, `:50`; `scripts/watch-coredump.py:19`; `H10-20:555-559` | entropy, klog | firmware | Do not plan on decoding dumps; keep in-process fault records. |
| F7 | The placed-alias lifecycle works on hardware: kernel aliases of Onion and Garlic, the primary survives unmapping the alias, `munmap` then reserve `FIXED`\|`0x80`, a remap at the same address, GPU copies, 4 KiB and 64 KiB BOs. | `FINDINGS.md:3546-3554`, `:3614-3624`, `:3660-3666` | vkmapprobe | no | It proves our mesa 0003 **fallback** order. Our first attempt, a fixed reserve over a live alias, is still unmeasured (`LOG.md:127`). |
| F8 | Images and other device-local buffers go to Garlic outside RADV's arena (`ORBIS_VRAM_GARLIC=0` keeps them inside). | `FINDINGS.md:1814-1823` | asserted (an email from nx-on-orbis' author; a fact) | no | The arena size is not Bloodlines' texture budget. |
| F9 | In a PRX that links static libc, `__tls_get_addr` returns NULL, so ACO's `thread_local` faults. | `FINDINGS.md:2030-2032`, `:3114-3124` | fault records | no | Keep libvulkan on emutls. We never measured native PRX TLS (`HANDOFF-e.md:279`). |
| F10 | Registry hives were zero bytes after a reboot, and Wine then refused the prefix. | `H10-26:1741-1760` | logs | no | With PS-button kills, back up `system.reg`/`user.reg` and Bloodlines' saves (`game.sh --saves-pull`). |
| F11 | Upstream's ImeDialog works unmodified on the PS4. `gethostname` returns "". Audio follows the console's HDMI output setting. | `H10-26:4474-4481`; `H10-20:2568`; `FINDINGS.md:3746-3752` | logs | no | low |
| F12 | `dup2` onto any free fd 64–255 fails; `sceKernelRdup` is EPERM; `F_GETFD` on fd 0 returns -1. `thr_self` and `thr_kill2` are not exported, but `pthread_getthreadid_np` is. | `FINDINGS.md:2277-2291`, `:1014-1018`, `:1408-1411` | probes | no | Confirms our dup route. |
| F13 | The same directory's `st_dev` changes between runs. | `FINDINGS.md:2178-2185` | probe | no | Do not key a cache on `st_dev` across launches. |
| F14 | In an eboot, crt1.o runs no constructors (a weak `_init` is the hook). An eboot's `DT_NEEDED` on an app PRX is not loaded. A `0x400000` ET_EXEC is refused, and a high PRX can release and reuse `0x400000`. **Correction (2026-11-02):** the last part is not a lowbase-probe result: `src/lowbase-probe/README.md:14-20` is an expected sequence, and no probe output exists in their docs or git log. The proof is their Wine runs that loaded EXEs at 0x400000 after the release (`HANDOFF-i.md`, B). **Measured on our Slim (2026-11-03, i1, LOG L16):** a high PRX released the stub's segments and reserved, mapped and ran code at 0x400000; the pad's init is the one call that failed after the release (`HANDOFF-i.md`, "i1 passed"). | `FINDINGS.md:2005-2009`, `:1945-1950`, `:2379-2395`; `src/lowbase-probe/README.md:9-20` | hardware | no | Only for row 16. |
| F15 | The profile's `show_fps` injects `DXVK_HUD=fps`, which overrides `dxvk.hud` in `dxvk.conf`. | `H10-20:3567-3576` | logs | no | Our `profiles/vtmb.ini` has `show_fps = true`. A `dxvk.hud` set in `dxvk.conf` will not show. |
| F16 | Translator against native for Oblivion: about 4–8 FPS against 35–50 FPS. | `H10-14:8503-8521`, `:7127-7132` | logs | Pro CPU | Native is right for Bloodlines. |
| F17 | Pro only: SFO ATTRIBUTE bit 24 (`0x00800000`) for Neo mode; device 0x9924, 4 SE, CU mask `0x3ef`; in Neo mode a draw of ≥257 primitives hangs while base mode passes. | `FINDINGS.md:397-426`, `:4013-4016`; `src/gfx-hang-probe/README.md:96-104` | hardware | **yes** | None for the Slim. |

### Where they contradict us

| Topic | Theirs | Ours | Better evidence |
|---|---|---|---|
| DXVK 3.x on GFX7 | DXVK 3.1.1 creates a device on mesa-ps4, and GTA IV loaded a scene with it (`FINDINGS.md:2711-2723`, `:3111`, `:3315-3323`) | "not 2.7+/3.x: they need Vulkan features GFX7 RADV lacks" (`CLAUDE.md`, Pins; `RESEARCH.md:103-106`, from release notes). Our e1 line has `maintenance5=1` (`LOG.md:85`). | **Theirs** (measured). Keeping 2.6.2 is still right (prospero-win's tuned build, batching, the `vampire.exe` profile), but the stated reason is wrong. |
| klog history | GoldHEN replays its buffer on connect (`FINDINGS.md:436-438`) | "plain stream, no history" (`CLAUDE.md`, Environment); one message was lost at a reconnect (`LOG.md:60`) | Theirs is one direct observation; it may depend on the GoldHEN version. Test once by connecting late. |
| GoldHEN FTP | An anonymous login, even a stray byte, kills FTP and klog (`FINDINGS.md:236-257`, `:1844-1866`) | Our `deploy.sh` and `runtime.sh` log in on every upload, including the 4.1 GiB game mirror | **Ours**, for our console |
| USB keyboard | "not an option on this console" (`FINDINGS.md:3789-3792`), never probed | libSceKeyboard opened and a key reached Wine (`LOG.md:130`) | **Ours** |
| VideoOut sizes | Only the video mode's size registers (`FINDINGS.md:3155-3158`, reasoning) | 1280x720 registers; 960x540, 800x600 and 3840x2160 are refused (`HANDOFF-p.md:558-561`, `HANDOFF-g.md:22`) | **Ours** (measured). Flipping 720p is untested. |
| Relative `open` | ENOENT for `"data/pkg"` (`FINDINGS.md:1090`) | EINVAL (`CLAUDE.md`, quoting orbis-compat) | Neither is strong. A relative open of an existing file settles it. |
| `readdir` on `/data`; where malloc lives | `readdir` gives EINVAL; libc malloc reached 1 GiB (`FINDINGS.md:944-956`, `:2550-2571`) | musl lists `/data`; malloc is flexible memory | Not a conflict: their libc is Sony's `libSceLibcInternal`. orbis-compat's `__mmap` hook (`refs/orbis-compat/src/orbis_mmap.cpp:461`) can serve musl's malloc from direct memory. Ours imports malloc from ntdll's heap, which is already in direct memory. |
| USB mouse | Never got data; loading libSceMouse correlated with a black-screen stall (`H10-20:3388-3431`) | 0 records from `sceMouseRead` (`HANDOFF-g.md:141-143`) | Nobody has mouse data yet; they offer no lead. |

### What we have that they lack (for a later upstream report)

- `O_NONBLOCK`: F_SETFL and FIONBIO return EACCES on AF_UNIX sockets but work on pipes. SCM_RIGHTS duplicates
  descriptors.
- VideoOut's hardware cursor plane on the PS4: straight-alpha ARGB, 1:1, 64x64, removed when the port closes.
- The VideoOut size table above.
- A 512 GiB `FIXED` reservation at `0x1000000000`.
- Cpuset `0x3f` at 1.59 GHz; pinning to cores 6/7 returns `0x80020001`.
- The SDK's `stack_t` swaps `ss_size` and `ss_flags`.
- Stack reuse by libthr, and caller-set stacks passed through untouched.
- Native WoW64 on a Slim: caps 7, far jump to `0x33`.
- `realpath` and the 134 ENOSYS libc stubs.
- A klog line costs 8–15 ms.
- FTP returns `.prx` files decrypted.
- Conditional rendering and draw-indirect-count hidden in the driver.
- PRX loader rules: no constructors, data imports bind, a mid-page PT_LOAD is ENOEXEC.
- CE-34878-0 on `exit()`; CE-33237-8 when installing over a running title.
- Fork patches 1120/1130 (decommit beside a read-only page with 16 KiB pages). Their tree lacks upstream 0974, which
  1120/1130 repair.
- Their tree also lacks upstream 0603, 0614, 0871 and 0970; 0973, 0974 and 0982 survive only in part.

## Tooling worth copying

- `scripts/watch-coredump.py`: fetch the exact coredump path GoldHEN announces, retrying for 20 s. Provenance only
  (F6). Rewrite it in bash per our rules.
- A pre-upload gate: package size against the last good one, a file-list diff, the separately built PRXs present
  (`H10-26:3986-4009`). Single-file A/B repackaging with hash checks (`scripts/repackage-orbis-ab.py`), and distinct
  title IDs so A and B install side by side (`H10-09:991-995`).
- Bounded, aggregated logging (`WP/0906`). Avoid per-page klog lines and `+file`/`+msg`/`+dinput`.
  Their Oblivion startup fell from 12 minutes once they did (`H10-14:8308-8336`).
- Critical-section wait stacks (`WP/0863`) and an umutex owner snapshot (`H10-20:5687-5700`) for deadlocks.
- No SIGPROF sampler: it crashed in libkernel through `FS:0x10` (`H10-14:6340-6372`).
- Scripted input replay (`PW_WINE64_SCRIPT=1`, `H10-20:4946-4953`), for a repeatable walk into a level.
- `WINEDEBUG` takes `warn+vulkan`, not `+warn+vulkan` (`H10-20:4116-4127`).

## Claims we cannot check

- **Four games at gameplay** (`README.md:15-22`, `docs/HARDWARE-STATUS.md:9-13`): GTA IV and Oblivion are
  log-confirmed in their handoffs (`H10-26:2759-2786`, `:4638-4660`; `H10-14:6508-6524`).
- **Fallout 3 "reaches gameplay and V.A.T.S."**: no handoff run shows Fallout 3 in gameplay.
- **Fallout NV's V.A.T.S. fault "guarded" by the profile**: the last handoff calls it unfixed (`H10-26:5492-5506`).
  Their `falloutnv-config/dxvk.conf` only sets `d3d9.maxAvailableMemory = 256`.
- **Oblivion at 50–60 FPS with music off**: the user's observation, Boost Mode state unknown (`H10-20:5-7`).
- **"An FTP login kills GoldHEN"**: no log (`H10-09:11-12`).
- **Upstream 0604 (commit stacks on demand) adds startup time**: inferred, not measured (`H10-26:4782-4787`). It is a
  candidate for our ~60 s first-menu time (`HANDOFF-g.md:150`), to measure, not to revert.
- Their GPU clock is given as 800 MHz (`FINDINGS.md:488-495`) and as 911 MHz (`UPSTREAM-REPORT.md:63`).

## Noticed, not changed here

- `ARCHITECTURE.md:115` and `:137` still say the PS4 has no hardware cursor (gc1 measured one).
- The DXVK pin reason in `CLAUDE.md` (see "Where they contradict us").
- Row 10 (`0xf2` on `__ORBIS__`) is ours to fix, whatever orbis-win does.

## FNV diagnosis for orbis-win (2026-11-03)

This was a side task: desk work on his `10-28-sync` and his 1086/1081 logs. Nothing ran on our console.

**Cause.**
- FalloutNV.exe and several of its DLLs lack NX_COMPAT. Wine therefore forces PROT_EXEC on every readable page
  (`dlls/ntdll/loader.c:1597`, `mprotect_exec`).
- On direct memory, his glue turns each such request into an exec migration to flexible memory (the "do not port"
  row above).
- That causes two problems:
  - Its copy-back runs over an already read/write mapping, so other threads read zeros and lose stores.
  - The migrated heap fills the flexible pool. The top holder was 138–191 MiB of RWX in 4,700–6,400 mappings at
    every FNV crash, with 1–29 MiB free.

**Fix.**
- An opt-in `PW_PS4_FORCE_EXEC=0` (his WP/1029, new code, LGPL) keeps no-exec on, so only real code pages ask for exec.
- He merged it as PR #1 (`e9b0db4`). FNV then ran 15+ minutes, where it had crashed after 1–5.

**Stacks.** His in-process wineserver thread asked for 1 MiB without a stack address, so the SDK interposer raised
it to the 16 MiB flexible floor. He moved it to a 1 MiB stack himself, from our description, and reports FNV still
works.

**Still open.** Real code pages still migrate, and F3 is unresolved.

**The full write-up is local and gitignored:** `build/orbis-win-10-28-diag/FNV-DIAGNOSIS.md`, with the logs and
patches beside it.

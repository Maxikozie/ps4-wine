# Porting prospero-win to a Jailbroken PS4 to Run Vampire: The Masquerade – Bloodlines: Feasibility Study and Roadmap

**This port is feasible, and someone has already done most of it.** Since 7 October 2026 a developer called plastikman has been running prospero-win on a PS4 Pro.\[1\] He reports Oblivion (GOG), Fallout: New Vegas, MDK and Space Cadet Pinball working, and GTA IV running "really slow, like 10 FPS" (issue #455, 9 October 2026). Those games are as heavy as Bloodlines or heavier. His PS4 tree is not public yet, but he has upstreamed two patches (#736 and #737).\[1\] So the best plan is not a clean-room port. Rebase on prospero-win, reuse the orbis-ports PS4 stack (OpenOrbis + orbis-compat + mesa-ps4 RADV), contact plastikman early, and aim for Bloodlines at playable but not locked frame rates, ideally on a PS4 Pro.

## TL;DR

- **Verdict: realistic, with caveats.** prospero-win puts the whole of Wine (PE DLLs, Unix side, wineserver) into one PS5 app process, so the same design carries over to the PS4. The x86-64 CPU and GCN GPU family are shared, a PS4 RADV with a video-out WSI already exists, and a PS4 build of prospero-win already runs 2004–2006-era D3D9 games. The main risks are CPU speed (Jaguar at 1.6/2.13 GHz), the roughly 4.5 GiB process memory budget, and whether the hardware 32-bit WoW64 path can be enabled on Orbis. The fallback translator costs speed.
- **Bloodlines specifically:** use the **GOG version** (DRM-free, Unofficial Patch included), or the Steam version with the Unofficial Patch, which no longer needs Steam to launch. It is 32-bit D3D9, so it takes the WoW64 + DXVK path that HL2 and GTA IV already use. Expect 30–60 FPS on a PS4 Pro and less on a base or Slim PS4. That is an estimate extrapolated from the GTA IV gap (PS5 ~59 FPS vs PS4 Pro "really slow, like 10 FPS" per plastikman in issue #455), not a measurement.
- **What to do:** develop on a **PS4 Pro with GoldHEN**. Pin DXVK **2.6.2** (prospero-win's own build), not DXVK 3.x. Follow the milestone ladder below: hello-world → triangle → Wine console → GDI → 32-bit → D3D9 → Bloodlines. Have Claude Code do everything it can on a Linux/FreeBSD host, and keep console runs for short, scripted validation.

## Key Findings

### 1. How prospero-win works internally

**Process model.** In the project's own description, Wine's "Windows DLLs, its Unix side and its server" all run "inside the PS5 app". Each game starts in a fresh process with its own Wine prefix, and closing it returns you to the launcher.\[2\] The PS5 Wine is WoW64-only: a 32-bit game still gets a 64-bit prefix.\[3\] Wine's Unix-side modules are built as PS5 PRX modules and loaded through a "PRX loader". The ntdll export descriptors are generated at build time (PR #430 describes publishing `__wine_prospero_native_wow64_caps` "in ntdll's descriptor only when it is a defined dynamic export").\[4\]

**Packaging and filesystem.**
- The app is a folder, `PPSA99995/`, copied to `/data/homebrew/` and registered by a loader such as ShadowMountPlus.\[5\]\[6\] PPSA99995 is "a local title ID we picked, not one assigned by Sony".\[2\]
- It was built on BlackBearReloaded's PS5 Native App Boilerplate.\[2\]
- Games, profiles, prefixes, saves and the RADV shader cache (`/data/prospero-win/cache/radv`) live under `/data/prospero-win`. Replacing the app folder keeps them.\[6\]\[7\]
- You need elfldr on port 9021, FTP, and a loader. The app bundles a "one-shot Lapy helper" (Lapy v0.3.2-experimental) and asks for `/data` access at startup.\[2\]\[6\] The homebrew catalog flags the app as one that "Leaves the sandbox" and ships a helper that runs outside it.\[5\] The project states the app itself "doesn't use firmware-specific offsets". The firmware-dependent parts are the jailbreak, the loader and the helper.\[2\]

**CPU paths. This is the most important part for the PS4.**
- **64-bit PE code** runs natively.\[2\]
- **32-bit code** had two backends by v0.2.0:
  - **The translator** (`wowprospero.dll`). This was prospero-win's own x86→x86-64 dynamic binary translator, the only 32-bit path in v0.1.x.\[7\] The project's own DBT benchmarks in prospero-win-profiles put it at about 85–93% of native speed on the PS5, after correcting for the x64 builds being "1.03–1.36× faster than the i386 ones" on the host. It did not implement SSE4.2, which is why v0.2.0 stopped advertising that feature to 32-bit programs.\[7\]
  - **The native WoW64 CPU** (`wow64native.dll`, PR #432, the default since v0.2.0).\[8\] It "prepares hardware compatibility-mode execution with the console selectors and restores host FS before Wine service calls".\[9\] In other words, it far-jumps into the CPU's 32-bit compatibility-mode code segment that the console kernel already defines, and runs the game's 32-bit code at full speed.
- Every guest→host crossing costs about **2.8 µs** on the PS5 ("two SET_FSBASE syscalls"). DXVK makes roughly 24,500 Vulkan calls per frame, which without batching would cap a game at about 13 FPS. prospero-win therefore batches 32-bit Vulkan calls (`PW_VK_BATCH=1`) into about 1,000 crossings per frame.\[8\] Measured results:

| Game | Translator | Native, no batching | Native + batching |
|---|---|---|---|
| GTA San Andreas | 38.0 FPS | 13.25 FPS | 59.92 FPS |
| GTA IV | ~45 FPS | — | ~59 FPS |

- The native backend needs to "register its signal handlers directly with the kernel".\[6\] It finds that entry point in libkernel and checks the kernel's signal-frame layout before using it. If the checks fail (as reported on FW 13.60), it falls back to the translator automatically (PR #677).\[6\]\[10\]
- OpenGL games stay on the translator, because GL calls cross one at a time and batching only covers Vulkan.\[8\]

**Memory, exceptions and threads (mihawk-99's fixes plus later ones).**
- Floating-point state is correct inside exception handlers.\[2\]\[6\]\[11\]
- Memory reserved at a fixed address and committed later is now backed properly. Steam's protection layer does this.\[6\]
- Recommitted memory comes back zeroed "even where the console's larger pages hold other data".\[6\]
- The usual Windows DLL load range is reserved at startup, so loading many DLLs no longer eats the console's smaller memory pool.\[7\]
- Games see 13 usable CPUs instead of 16.\[6\]
- Process memory counters, CPU times and directory change notifications now work.\[2\]\[6\]
- v0.3.0 (29 October 2026) changed several more things:
  - Games now see the console's real 12 GiB.\[5\]
  - Wine's own heap moved out of the game's flexible memory.\[5\]
  - Thread and fiber stacks follow Windows sizes.\[5\]
  - 64-bit games can reserve up to 512 GiB of address space.\[5\]
  - Write-protecting 4 KB pages now works.\[5\]
- Optional profile settings: `thread_scheduling` (round-robin scheduling and Windows thread priorities) and `fast_clock`.\[6\]

**Graphics, input and audio.**
- D3D8–11 run through DXVK (2.6.2, or the tuned 2.6.2-prospero2) on Vulkan RADV.\[2\]\[6\]
- OpenGL runs through Mesa Zink since v0.2.0.\[6\]
- D3D12 runs through vkd3d-proton 3.0.1 at feature level 11_1 since v0.3.0.\[5\]
- GDI and movies use the app's own display path.\[2\]
- DualSense (with XInput mapping), USB keyboard and mouse, and audio all go through the PS5's own system services.\[2\]
- The launcher handles per-game profiles, control presets and install recipes. Games are installed on a Linux PC with a matching desktop Wine build, then transferred.\[2\]\[3\]

**What is PS5-specific and what carries over:**

| Component | Status for a PS4 port |
|---|---|
| Wine PE/Unix split, in-process wineserver, launcher, profiles, Vulkan batching, recipes | Carries over almost as-is |
| Translator (`wowprospero.dll`) | Carries over (plain x86-64 code), but slower on Jaguar |
| Native WoW64 (`wow64native.dll`) | Depends on Orbis kernel selectors and signal frame. **Unverified on the PS4** |
| PRX packaging and loader, PS5 payload SDK build | Rewrite for OpenOrbis (OELF/eboot, fake PKG) |
| RADV winsys/WSI | Swap the PS5 RADV for mesa-ps4 (Liverpool/Gladius, sceVideoOut WSI) |
| DualSense, audio, OSK services | Swap for DualShock 4 (libScePad), sceAudioOut, PS4 IME |
| Lapy helper, `/data` elevation, ShadowMountPlus | Replace with GoldHEN (jailbreak, FTP, BinLoader, debug settings) |

### 2. PS5 vs PS4 homebrew environment

- **OS base:** Orbis is based on FreeBSD 9 (per the PS4 system-software record, whose latest firmware is 14.00 from 16 September 2026), Prospero on FreeBSD 11. The libkernel, syscall numbers and signal-frame layouts differ, so every place where prospero-win checks "the kernel's signal frame" or `SET_FSBASE` must be re-derived for the PS4.
- **SDK traps the orbis-ports team documented on real hardware:**
  - The OpenOrbis SDK "ships musl's headers over Sony's implementation", and they disagree structurally (for example `struct stat`).\[12\]
  - Raw syscalls are refused (`syscall(SYS_getpid)` returns errno 78), and raw `_umtx_op` returns ENOSYS.\[12\]
  - Relative `open` returns EINVAL and `getcwd` returns ENOSYS.\[12\]
  - `scePthreadCreate` gives each thread a 64 KiB stack. The overlay raises this to 2 MiB.\[12\]
  - `timer_create` with SIGEV_THREAD never returns.\[12\]
  - Returning from `main()` is reported as a crash (CE-34878-0).\[12\]
  - JIT memory has to be allocated through orbis-compat's `orbis_jit_alloc*` API: "nothing reaches it through mmap".\[12\]
  
  Each of these hits Wine's Unix side directly: path handling, futex-style waits, threads, timers, and executable memory for the translator.
- **Memory budget:** one PS4 Pro homebrew process got about **4.6 GiB of direct memory** (nx-on-orbis notes "the package layout that grants 4.4 GiB").\[13\]\[14\] Another port found the flexible pool to be about 400 MB, which pthread stacks exhaust quickly. It also needed a larger GPU arena (`ORBIS_ARENA_MIB=2048`) because the default 1 GB was eaten by 512 MB of shared memory.\[15\] The PS5 offers 12 GiB, so Wine's heap, DXVK's allocations and the game must all fit in about a third of that. A 32-bit game like Bloodlines can only address up to 4 GB anyway, so this is tight but workable.
- **GoldHEN** supplies:
  - the homebrew enabler and fake-PKG installs\[16\]
  - debug settings
  - an FTP server on port 2121\[16\]
  - a BinLoader on port 9090\[16\]
  - klog settings\[16\]
  - remote package install\[16\]
  
  Recent reports say GoldHEN covers firmware 7.00 through 13.52, after a September 2026 exploit chain.\[17\] Some older guides still say 13.00 is the ceiling.\[18\] Trust the newer, release-specific sources, but check your own firmware.
- **Toolchain:** OpenOrbis v0.5.4 (LLVM 18) plus orbis-compat. orbis-ports shipped them as one bundle, `orbis-sdk-v1`, with Mesa `orbis-mesa-1a59cc147b54` (26.3.0-devel).\[19\] orbis-porting-kit was archived on 21 September 2026 and is reportedly superseded by "orbsdk", a single owned sysroot.\[19\]\[20\] Check which one is current before pinning.

### 3. GPU and graphics feasibility

- **mesa-ps4** is RADV with "a no-DRM winsys arm, CHIP_LIVERPOOL/GLADIUS, and a video-out WSI".\[21\] Presentation goes through `VK_EXT_headless_surface`, which `wsi_orbis.c` turns into `sceVideoOutRegisterBuffers` + `sceVideoOutSubmitFlip`. A triangle example was verified on hardware on 17 September 2026.\[12\]\[21\]
- **The Vulkan version was not confirmed from orbis-ports' own dumps.** Upstream RADV was marked Vulkan 1.3 conformant on GFX6/GFX7 in Mesa 24.3 (its release notes list "radv: mark some GFX6-7 GPUs as Vulkan 1.3 conformant"), and this fork is Mesa 26.3-devel, so Vulkan 1.3 is the likely baseline. More decisive: plastikman's PS4 Pro runs prospero-win's DXVK path for GTA IV, Oblivion and Fallout NV, so DXVK 2.6.x's hard requirements must be met in practice. Verify with `vulkaninfo`-style dumps in milestone (b).
- **Choosing a DXVK version:**
  - DXVK 2.0+ requires Vulkan 1.3.\[22\]\[23\]
  - DXVK 2.7's release notes state that "The Vulkan extension VK_KHR_maintenance5 is now required".
  - The newest releases (3.x) require Vulkan 1.4-era driver support, which GFX7 RADV does not offer upstream.\[24\]\[25\]
  - **So pin DXVK 2.6.2 or 2.6.2-prospero2**, matching prospero-win. DXVK 1.10.x is a fallback if a 1.3 feature turns out broken.
- **Known driver behaviour:**
  - Linear 3D surfaces and disabled tessellation are now driver defaults (`ORBIS_3D_LINEAR`, `ORBIS_NO_TESS`).\[12\] D3D9 does not need tessellation, so this is harmless for Bloodlines.
  - One GPU stall persists, at about one submit in 1,200.\[12\]
  - nx-on-orbis saw red and blue swapped across the whole image, suspected to be a presentation-path bug.\[13\] Watch for this in your WSI.
- **D3D9 alternatives:** WineD3D-over-Zink is possible because Zink ships with prospero-win and works over the PS4 RADV, as RPCS3's PS4 port uses it.\[26\] It would stack two translation layers on a weak CPU, though. Gallium Nine needs a native Gallium driver, which does not exist here. DXVK's D3D9 is the right choice.
- **PS4 model differences:**
  - Base/Slim: GCN with 18 CUs at 800 MHz (1.84 TFLOPS).\[27\]
  - Pro: 36 CUs at 911 MHz (4.2 TFLOPS).\[27\]
  - All models have 8 GB GDDR5.\[27\]
  
  Bloodlines is not GPU-bound on either.

### 4. CPU and performance feasibility

- Jaguar runs at 1.6 GHz on the base/Slim and 2.13 GHz on the Pro.\[27\] The PS5's Zen 2 is several times faster per thread. The only PS4 data point is plastikman's GTA IV, which he described as "really slow, like 10 FPS" (issue #455, 9 October 2026), against about 59 FPS on the PS5: roughly a 6× gap for a heavy, CPU-bound 2008 game.
- Syscall and FS-base switch costs will be higher on Jaguar, so **Vulkan batching is mandatory, not optional**.
- **Native 32-bit execution on the PS4:** the PS5 backend relies on the "console selectors", which are compatibility-mode code and data segments already in the kernel's GDT. Stock FreeBSD amd64 defines 32-bit user selectors for its compat32 ABI, and Orbis is FreeBSD-derived. So it is plausible, but not verified, that the same far-jump works on the PS4. If it does not, GoldHEN's kernel read/write could install a selector, but that would be firmware-specific and fragile. Either way, the translator remains the fallback.
- **Bloodlines:** an early Source engine game from 2004, 32-bit, D3D9, mostly single-threaded. The Wine/Proton community reports it plays well with the Unofficial Patch (UP 11.5).\[28\]\[29\] It is lighter than Oblivion and GTA IV, which already run on the PS4 build. **Estimate:** 30–60 FPS on the Pro with native WoW64 and batching, and lower (perhaps 20–40 FPS) on a base PS4 or on the translator. The engine's own hitches when loading hubs will be worse on the PS4's HDD.

### 5. Prior art and community

- **plastikman** (GitHub `plastikman`) opened issue #455 on 7 October 2026 with a PS4 Pro build of prospero-win, and on 14 October 2026 reported "a patch set ready that allows the ORBIS to build along side the PROSPERO". The upstream maintainer asked him to keep it in a separate fork and send console-agnostic fixes upstream. #737 lets non-relocatable EXEs load. **He is the single most important contact.**
- **orbis-ports** (Mikołaj Mikołajczyk): mesa-ps4, orbis-compat, the porting kit, Vulkan CTS on the console, and ports of OpenGothic, RetroArch and Panda3DS.\[30\] Mesa upstreaming was closed on 21 August 2026.\[26\]\[31\]
- **nx-on-orbis** (alechurri) is a PS5→PS4 port (Eden) built with Claude.\[13\]\[32\] Its docs on memory, faults and address-space limits are directly reusable.\[13\]
- **Other ports on the same stack:** RPCS3's PS4 port uses Mesa EGL and Zink over RADV, and a Skate 3 recompilation port documents memory-pool traps.\[15\]\[26\]
- **Wine itself:** Wine 11.14 (24 July 2026) added initial WoW64 mode on FreeBSD, running 32-bit Windows software on purely 64-bit system libraries, which makes a FreeBSD host a useful off-console test bed.
- **Earlier speculation:** WineHQ and GBAtemp threads (2018–2019) asked whether Wine could be ported to Orbis but produced nothing.\[33\]\[34\]
- **Other contacts:** mpereiraesaa (prospero-win maintainer), leolobato (Playden, prospero-win contributor) and mihawk-99 (PS5 Wine/Mesa fixes).\[2\]\[10\]

## Details: Subsystem Porting Map

| Subsystem | prospero-win (PS5) | PS4 equivalent | Work needed |
|---|---|---|---|
| Boot / app shell | Native App Boilerplate, PPSA99995, Lapy helper | OpenOrbis eboot + fake PKG (`make-pkg.sh`), GoldHEN | New package and title ID (for example a `CUSA`-style fake ID). Idle instead of returning from main |
| libc / pthread | PS5 payload SDK libc | OpenOrbis musl headers + orbis-compat corrections | Link orbis-compat `--whole-archive`. Fix stat, umtx, stacks, getcwd and relative paths in Wine's Unix side |
| Memory | Fixed-address reserves, decommit, 12 GiB | Direct memory about 4.4–4.6 GiB, small flexible pool, `orbis_jit_*` | Re-tune reservations, move Wine heap and stacks into direct memory, route translator code buffers through `orbis_jit_alloc` |
| Signals / SEH | Direct kernel signal registration, frame-layout check | FreeBSD 9 signal frame, different libkernel | Re-derive offsets on the PS4. Keep the "check, then fall back" design |
| 32-bit CPU | `wow64native` (compat-mode selectors) + translator | Unknown selector support; translator works | Ship the translator first, then probe for native |
| Threads / affinity | 13 usable CPUs, round-robin option | Games get fewer cores (6–7 usable is typical; verify) | Report the real count, re-tune `thread_scheduling` |
| Filesystem | `/data/prospero-win`, `/data/homebrew` | `/data/...` over GoldHEN FTP, absolute paths only | Path layer that resolves cwd-relative paths in Wine |
| Vulkan | PS5 RADV + loader | mesa-ps4 + orbis vkloader (771 weak thunks) | Point Wine's winevulkan at the vkloader shim |
| WSI / display | App display path | `wsi_orbis.c` (headless surface → sceVideoOut) | Hook Wine's display driver and GDI blits to sceVideoOut |
| Input | DualSense, USB KB/M | libScePad (DS4), USB KB/M | Port the input backend. SDL2-orbis is an option |
| Audio | PS5 audio service | sceAudioOut (proven clean in nx-on-orbis) | New winepulse-style backend, or use SDL2 audio |
| Networking / TLS | Console resolver, GnuTLS schannel | PS4 libSceNet | Low priority for Bloodlines |

## Recommendations: Milestone Roadmap

Each step has a single, unambiguous pass/fail check that Claude Code can script.

| # | Milestone | Success check | Main risk |
|---|---|---|---|
| a | Toolchain + hello-world PKG with klog/netlog | `orbis-sdk bundle: all checks passed` in logs | Header/ABI mismatches. Use the bundled, fingerprinted SDK |
| b | Vulkan triangle via mesa-ps4 + capability dump | Triangle on TV. Device reports Vulkan 1.3 with `maintenance5`, `robustness2` (nullDescriptor), `graphics_pipeline_library`, `transform_feedback` | Missing extension blocks DXVK 2.6, so fall back to 1.10.x |
| c | Wine core boots a 64-bit console EXE | `hello.exe` prints over netlog. In-process wineserver survives | Signal frame, umtx, paths and stacks |
| d | winemine / notepad (GDI) | Minesweeper playable with DS4 | Display path, input |
| e | 64-bit D3D11 sample via DXVK | Frame presented, no GPU hang | Memory arena sizing |
| f | 32-bit EXE via translator, then native WoW64 probe | Pinball runs. Log equivalent of `caps=7` for native | Executable memory (JIT API), compat selectors |
| g | 32-bit D3D9 Source game (HL2) with batching | Stable 30+ FPS on the Pro, crossings per frame logged | CPU budget, shader-compile stalls (keep the RADV cache) |
| h | Bloodlines (GOG + UP) | New game → Santa Monica hub, save/load, 30-minute session | Memory peaks, hub load hitches, relocation (#737) |

**Practical advice:**
1. **Before writing code, ask plastikman for early access** or wait for his fork. Starting from his patch set could turn milestones (a)–(f) from months into days. Build your work as PRs against it.
2. **Hardware:** use a PS4 Pro (2.13 GHz, 4.2 TFLOPS) on a GoldHEN-supported firmware (12.02 is proven by nx-on-orbis).\[13\]\[27\] Add Ethernet for FTP and netlog. An internal SSD is worth it for Bloodlines' hub loading.
3. **Host:** x86_64 Linux with clang/lld 18, cmake, ninja, meson, glslang, mingw-w64 (i686 + x86_64) for Wine's PE side, and Python 3. Optionally add a FreeBSD 14/15 VM to test Wine's FreeBSD WoW64 path off-console.
4. **Iteration loop:**
   - build
   - `make-pkg.sh`
   - `deploy.sh` over GoldHEN FTP/remote install, or send ELFs to BinLoader on port 9090
   - capture logs with `logs.sh`/klog
   - symbolize crash offsets against the exact ELF (nx-on-orbis ships the ELF next to the PKG for this)\[32\]
5. **Using Claude Code:**
   - Give it a CLAUDE.md that states the PS4 traps listed above.
   - Make it write host-side unit tests first. prospero-win's `make all` already runs 61 C tests and 53 Python suites with no console.\[8\]
   - Batch several hypotheses into each console build. nx-on-orbis ran 29 console builds in five days.\[13\]\[32\]
   - Give every console run a machine-readable log line, so you can paste the results back to the agent.
6. **Effort:** with plastikman's base, expect weeks to about two months part-time to reach Bloodlines. From scratch, expect 6–12 months. The hard parts are signals/SEH, memory and the 32-bit path, not graphics.

## Caveats

- **Legal and licensing:**
  - prospero-win is LGPL-2.1-or-later.\[2\] A fork must keep the licence, provide the source for distributed binaries (including Wine patches), and keep `THIRD_PARTY.md`, `LICENSES/` and `SOURCES.txt` up to date.\[6\]\[35\]
  - nx-on-orbis is GPL-3.0. orbis-compat and the porting kit are MIT, except that `orbis-tls.ld` is GPL-3.0-only.\[13\]\[19\]
  - Use only the OpenOrbis SDK. Never use leaked Sony SDK code.
  - Ship no game files. Own the game. Do not bypass DRM. The GOG release is DRM-free, and the Steam release can run without Steam once the Unofficial Patch is installed.\[36\]
- **Source quality:**
  - Most evidence comes from fast-moving GitHub repos written partly by AI agents. orbis-ports itself warns that "a record goes stale in a way code does not".\[31\]
  - plastikman's PS4 results are self-reported in an issue thread, not reproducible yet.\[1\]
  - The Bloodlines frame-rate figures are estimates.
- **Unverified:** whether Orbis exposes usable 32-bit compatibility selectors, and the exact Vulkan feature list of mesa-ps4. Both are first-week checks.

## Repos and Docs to Feed Claude Code

- prospero-win (README, `docs/ARCHITECTURE.md`, `docs/WINE_PS5_BUILD.md`, `docs/DEVELOPMENT.md`, `COMPATIBILITY.md`, PRs #429–#432, #677, #681, #736, #737, issue #455): github.com/mpereiraesaa/prospero-win
- prospero-win releases v0.2.0 and v0.3.0, and the tuned DXVK fork: github.com/mpereiraesaa/dxvk (tag v2.6.2-prospero2)
- prospero-win-profiles (benchmarks, recipes): github.com/mpereiraesaa/prospero-win-profiles
- Playden for PS5: github.com/leolobato/playden-ps5
- orbis-ports: mesa-ps4, ps4-mesa-docs (`docs/HANDOFF.md`, `cts.md`, `notes/`), orbis-compat (README §0–§9), orbis-porting-kit release `orbis-sdk-v1`, and orbsdk if published
- nx-on-orbis (`docs/STATUS.md`, `docs/TECHNICAL.md`, `docs/BUILDING.md`): github.com/alechurri/nx-on-orbis
- OpenOrbis PS4 Toolchain: github.com/OpenOrbis/OpenOrbis-PS4-Toolchain
- GoldHEN: github.com/GoldHEN/GoldHEN
- DXVK driver-support wiki and release notes (2.0, 2.6, 2.7, 3.x): github.com/doitsujin/dxvk
- Wine 11.14+ FreeBSD WoW64 work: gitlab.winehq.org/wine/wine
- Bloodlines: PCGamingWiki page, Unofficial Patch (moddb), ProtonDB app 2600

## Sources

1. [\[Feature\] PS4 support · Issue #455 · mpereiraesaa/prospero-win · GitHub](https://github.com/mpereiraesaa/prospero-win/issues/455)
2. [GitHub - mpereiraesaa/prospero-win: Windows compatibility runtime for native PlayStation 5 homebrew.](https://github.com/mpereiraesaa/prospero-win)
3. [ps5-prospero-win/docs/INSTALLING\_GAMES.md at main · leecloudvictor/ps5-prospero-win · GitHub](https://github.com/leecloudvictor/ps5-prospero-win/blob/main/docs/INSTALLING_GAMES.md)
4. [wow64: build the native backend and expose ntdll readiness by mpereiraesaa · Pull Request #430 · mpereiraesaa/prospero-win · GitHub](https://github.com/mpereiraesaa/prospero-win/pull/430)
5. [Prospero Win — PS5 Homebrew Store](https://prosperostore.net/app/PPSA99995/)
6. [Release prospero-win v0.2.0 · mpereiraesaa/prospero-win](https://github.com/mpereiraesaa/prospero-win/releases/tag/v0.2.0)
7. [Releases · mpereiraesaa/prospero-win · GitHub](https://github.com/mpereiraesaa/prospero-win/releases)
8. [Run 32-bit games on the native WoW64 CPU with Vulkan batching by default by mpereiraesaa · Pull Request #432 · mpereiraesaa/prospero-win](https://github.com/mpereiraesaa/prospero-win/pull/432)
9. [wow64: add gated hardware compatibility backend by mpereiraesaa · Pull Request #429 · mpereiraesaa/prospero-win · GitHub](https://github.com/mpereiraesaa/prospero-win/pull/429)
10. [wow64: run on the translator when the native CPU does not start by leolobato · Pull Request #677 · mpereiraesaa/prospero-win · GitHub](https://github.com/mpereiraesaa/prospero-win/pull/677)
11. [GitHub - Sleepywalker69/prospero-win: Windows compatibility runtime for native PlayStation 5 homebrew. · GitHub](https://github.com/Sleepywalker69/prospero-win)
12. [GitHub - orbis-ports/orbis-compat: The PlayStation 4 platform overlay: OpenOrbis toolchain files, libc and pthread shims, a Vulkan loader shim, packaging and console logging. Every other repository in this org depends on it.](https://github.com/orbis-ports/orbis-compat)
13. [GitHub - alechurri/nx-on-orbis: Experimental port of the Eden Switch emulator to a jailbroken PS4 Pro (closed experiment, open for anyone to continue). Not affiliated with Eden; built with AI. No keys, firmware or games.](https://github.com/alechurri/nx-on-orbis)
14. [GitHub - makinhu/nx-on-orbis: Experimental port of the Eden Switch emulator to a jailbroken PS4 Pro (closed experiment, open for anyone to continue). Not affiliated with Eden; built with AI. No keys, firmware or games. · GitHub](https://github.com/makinhu/nx-on-orbis)
15. [GitHub - OnlyMoisties/skate3-ps4 · GitHub](https://github.com/OnlyMoisties/skate3-ps4)
16. [GoldHEN PS4 - (Exploits) - GameBrew](https://www.gamebrew.org/wiki/GoldHEN_PS4)
17. [How to Jailbreak Your PS4 with GoldHEN on Firmware 7.00 to 13.52 (Step by Step) - Doctor Glitch](https://doctorglitch.com/ps4-jailbreak-goldhen-firmware-7-00-13-52/)
18. [PS4 Jailbreak Complete Guide 2026 - Firmware, Exploits, GoldHEN, Homebrew](https://www.ps4home.com/ps4-jailbreak/)
19. [Release orbis-sdk-v1 · orbis-ports/orbis-porting-kit](https://github.com/orbis-ports/orbis-porting-kit/releases/tag/orbis-sdk-v1)
20. [GitHub - orbis-ports/orbis-porting-kit: PS4 porting kit: toolchain, CI and the Vulkan loader shim. Copy-phase; see README. · GitHub](https://github.com/orbis-ports/orbis-porting-kit)
21. [GitHub - orbis-ports/mesa-ps4: RADV on the PlayStation 4 (Orbis). Mesa fork: a no-DRM winsys arm, CHIP\_LIVERPOOL/GLADIUS, and a video-out WSI. · GitHub](https://github.com/orbis-ports/mesa-ps4)
22. [github.com](https://github.com/doitsujin/dxvk/wiki/Driver-support/f5af9c51227a8fc1fd41d62e88af2ff6820b9513)
23. [DXVK 2.0 Released With Many Improvements For Direct3D Over Vulkan - Phoronix](https://www.phoronix.com/news/DXVK-2.0-Released)
24. [DXVK - Vulkan Translation Layer for Morrowind and MGE XE at Morrowind Nexus - Mods and community](https://www.nexusmods.com/morrowind/mods/53685)
25. [DXVK](https://en.wikipedia.org/wiki/DXVK)
26. [GitHub - RoberixStudios/rpcs3-port-for-ps4 · GitHub](https://github.com/RoberixStudios/rpcs3-port-for-ps4/)
27. [PlayStation 4](https://en.wikipedia.org/wiki/PlayStation_4)
28. [ProtonDB](https://www.protondb.com/app/2600)
29. [Vampire: The Masquerade - Bloodlines](https://steamcommunity.com/app/2600/discussions/0/4849903159938843027)
30. [GitHub - JiovanyMatos51/rpcs3-port-for-ps4 · GitHub](https://github.com/JiovanyMatos51/rpcs3-port-for-ps4)
31. [GitHub - orbis-ports/ps4-mesa-docs: The record of the PS4 RADV port: the running handoff, the implementation plan, five research investigations, captured radeon\_info dumps, and how to run the Vulkan CTS on the console.](https://github.com/orbis-ports/ps4-mesa-docs)
32. [Release v0.1.0: races at 13-16 fps (closed experiment) · alechurri/nx-on-orbis · GitHub](https://github.com/alechurri/nx-on-orbis/releases/tag/v0.1.0)
33. [¿Could wine be ported to PS4 SDK? - WineHQ Forums](https://forum.winehq.org/viewtopic.php?t=30665)
34. [Microsoft Windows Games ON PS4 (WineHQ implementation on OrbisOS ) DEAD SPACE - CUPHEAD](https://gbatemp.net/threads/microsoft-windows-games-on-ps4-winehq-implementation-on-orbisos-dead-space-cuphead.527728/)
35. [GitHub - vvsx87/prospero-win · GitHub](https://github.com/vvsx87/prospero-win)
36. [Vampire: The Masquerade - Bloodlines](https://www.pcgamingwiki.com/wiki/Vampire:_The_Masquerade_-_Bloodlines)

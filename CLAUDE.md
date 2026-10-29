# ps4-wine

Wine for a jailbroken PS4 Slim (Orbis OS, OpenOrbis toolchain, GoldHEN), built
on prospero-win's design: Wine's PE side, Unix side and wineserver all inside
one PS4 title, 32-bit games on prospero-win's translator (native WoW64 when the
console allows it), Direct3D through DXVK 2.6.2 on mesa-ps4's RADV. Target:
Vampire: The Masquerade – Bloodlines (GOG + Unofficial Patch). 32-bit D3D9
games in general are the goal; 64-bit is a stepping stone.

Read in this order: `docs/ps4/ARCHITECTURE.md` (what carries over, what is
rewritten), `docs/ps4/MILESTONES.md` (a–h, one pass/fail check each),
`docs/ps4/LOG.md` (every console run), `docs/ps4/RESEARCH.md` (background).
`refs/` holds read-only reference checkouts (`THIRD_PARTY.md` lists them).

## Hard rules

- **Licence.** This repo is GPL-3.0 (`LICENSE`). Code from `refs/` may be
  reused. Every reused block carries the comment
  `From: <repo> <path> @ <commit> (<licence>)` and a row in `THIRD_PARTY.md`.
- **Upstream boundary.** Code meant for prospero-win (everything under
  `third_party/prospero-win`, our fork, and `upstream/*.patch`) is
  LGPL-2.1-or-later. It must not contain code from nx-on-orbis (GPL-3.0), nor
  orbis-compat's `orbis-tls.ld` (GPL-3.0-only), nor name this repo. Facts and
  measured offsets from those sources are fine; their code is not.
- **Inputs.** OpenOrbis only, never a leaked Sony SDK. No game files, no
  `.exe`/`.dll` tracked (gitignored). GoldHEN is a given: no exploit work, and
  title code never depends on firmware-specific kernel offsets.
- **Languages.** C for runtime code, in Wine's style. Bash for tooling,
  `set -euo pipefail`, `--help` on every script. Python 3 stdlib only where
  bash is not enough.
- **Pins.** Wine `490f6d5dcbb2a5047345b8af88d114bbcaad69a8` (prospero-win's),
  DXVK 2.6.2 (not 2.7+/3.x: they need Vulkan features GFX7 RADV lacks),
  OpenOrbis v0.5.4 (`toolchain-llvm-18.tar.gz`), mesa-ps4 `1a59cc1`,
  prospero-win `0e7b6b4`. Bump a pin in its own commit with the reason.
- **Evidence.** Host tests first; a console build should test several
  hypotheses at once. Every console launch appends exactly one line to
  `docs/ps4/LOG.md` in its documented format. Say plainly which console
  behaviour was not tested. Never edit a hash or a threshold to make a check
  pass.
- **Division of labour.** The user launches apps on the PS4 by hand and plays.
  Claude builds, packages, deploys, reads logs and takes screenshots.
- **Git.** The user commits. Do not commit or push unless asked. Never touch
  `refs/`.

## Environment

| What | Value |
|---|---|
| PS4 Slim | `192.168.8.184`, GoldHEN. FTP `2121` (serves the real root), klog TCP `3232` (plain stream, no history), BinLoader `9090` (only while enabled in GoldHEN) |
| Our netlog | UDP `18194` from the title to this host (orbis-compat's netlog scheme) |
| Console paths | packages `/data/pkg/`, our data `/data/ps4-wine/{prefix,profiles,logs,cache}`, installed app `/user/app/<TITLE_ID>/` |
| Title | `PSWN00001`, content `IV0000-PSWN00001_00-PS4WINE000000000` |
| Host | Kubuntu (Ubuntu 26.04), x86_64. Toolchain at `$OO_PS4_TOOLCHAIN` (default `~/.local/opt/openorbis`); `common.sh` puts `/usr/lib/llvm-18/bin` first in PATH and sets `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` (PkgTool.Core cannot load ICU 78) |
| Screen | USB HDMI capture stick, `scripts/ps4/shot.sh` (auto-detects; the laptop webcam is excluded; override with `PS4_CAPTURE_DEV`) |

## Scripts (`scripts/ps4/`)

| Script | Does |
|---|---|
| `setup-host.sh` | prints missing apt packages (never sudo); `--install-toolchain` (OpenOrbis v0.5.4, sha256-pinned); `--install-openssl11` (private OpenSSL 1.1 that PkgTool.Core's `pkg_build` needs) |
| `build.sh <target>` | `--check-toolchain`; `compat` (orbis-compat → `build/orbis-compat`), `mesa` (mesa-ps4 RADV, no nix, local clone → `build/mesa-ps4`), `probe` (→ `dist/probe-<id>.pkg`), `probe-test` (host tests); later targets fill in per milestone |
| `pkg.sh --elf X` | ELF → fSELF → `.pkg` in the layout that grants ~4.4 GiB direct memory |
| `deploy.sh FILE` | `.pkg` over FTP to `/data/pkg` (optionally remote-install); `.elf` to BinLoader |
| `logs.sh` | klog (3232) + netlog (18194) merged into `logs/<ts>-<label>.log`; `--expect REGEX --timeout S` gates |
| `shot.sh` | one frame from the capture stick; `--pixel X,Y`, `--expect-rgb` |
| `check.sh <a-h>` | the milestone's single pass/fail rule; prints the LOG.md line |

The loop for one console run: `logs.sh --label X &` (klog has no history, so
start it first) → `deploy.sh` → the user launches → `logs.sh --expect` /
`check.sh` → `shot.sh` → one line in `docs/ps4/LOG.md`.

## PS4 traps (measured by orbis-ports, nx-on-orbis, playden; see ARCHITECTURE.md)

- The SDK ships musl headers over Sony's FreeBSD-9-derived libc: `struct stat`
  (`mode_t`), pthread attr sizes and `bits/signal.h` are wrong. Build with
  orbis-compat's overlay ahead of the SDK and `-include orbis_prefix.h`.
- A raw `syscall` instruction outside libkernel kills the process; libc
  `syscall()` returns ENOSYS. Relative `open` is EINVAL, `getcwd` ENOSYS,
  `fchdir` crashes, `openat` takes only `AT_FDCWD`. Use absolute paths.
- Default thread stack is 64 KiB (orbis-compat raises it to 2 MiB).
  `timer_create` with SIGEV_THREAD hangs. `sigaltstack` returns -1.
- Returning from `main()` or calling `exit()` is reported as CE-34878-0: idle
  forever instead.
- Executable memory: `sceKernelAllocateDirectMemory` → map RW → `sceKernelMprotect`
  RWX. Asking for EXEC at map time fails. Page granule 16 KiB.
- Flexible memory (`mmap(MAP_ANON)`, libc malloc) is ~384–440 MiB. Direct
  memory is ~4.4 GiB **only** with the OpenOrbis-samples package layout
  (`sce_module/libc.prx` + `libSceFios2.prx`, `sce_sys/about/right.sprx`,
  SFO `CATEGORY gd`, `SYSTEM_VER 0`, paid `0x3800000000000011`). Other layouts
  give 768 MiB or do not boot. Largest `sceKernelReserveVirtualRange`: 16 GiB.
- Faults come through `sceKernelInstallExceptionHandler` or FreeBSD `sigaction`
  (FreeBSD flag values and struct layout, not the SDK's): both give the PS5's
  frame, measured 2026-10-30: mcontext at ucontext+64 (rip +224), FXSAVE +320,
  FS base +1152, cs64 `0x43`. `sysarch` 128–131 get/set FS and GS; `rdfsbase`
  is SIGILL. A far jump to selector `0x33` runs 32-bit code and returns.
- `sceSystemServiceLoadExec(path, args)` restarts the title; the new process
  gets the arguments from `argv[0]` on (no program name). An app PRX loads from
  `/app0/assets` and `sceKernelDlsym` resolves its exports (link it
  `--export-dynamic`), but its constructors did not run even with
  orbis-compat's `crtlib.o` (the SDK's never walks `.init_array`).
- `libc.a` was built with a 16-bit `wchar_t`: `wmemchr` and friends are wrong
  for 4-byte `wchar_t`. `secure_getenv` always returns NULL.
- `sceKernelDebugOutText` (klog) costs 8–15 ms per line and blocks when nothing
  drains it: netlog for volume, klog for startup and fatal lines only.
- Vulkan (RADV, "PlayStation 4 Liverpool", GFX7, Vulkan 1.3): a submission
  must fit 2 MiB (524288 dwords) or the GPU hangs; `VK_EXT_conditional_rendering`
  and `VK_KHR_draw_indirect_count` hang the GPU; about one submit in 1200
  stalls; surface formats are RGBA only (BGRA swaps red and blue); arena size
  via `ORBIS_ARENA_MIB`. Vulkan titles link `libvulkan_radeon.a` with
  `--whole-archive` plus the kit's vkloader thunks.
- Compile with `-march=btver2 -femulated-tls -fno-omit-frame-pointer`. The
  title's cpuset is `0x3f`: 6 Jaguar cores at 1.59 GHz (Slim, TSC 1594 MHz);
  pinning to cores 6/7 returns `0x80020001`.

# ps4-wine

Wine for a jailbroken PS4 Slim (Orbis OS, OpenOrbis toolchain, GoldHEN), built
on prospero-win's design: Wine's PE side, Unix side and wineserver all inside
one PS4 title, 32-bit games on prospero-win's translator (native WoW64 when the
console allows it), Direct3D through DXVK 2.6.2 on mesa-ps4's RADV. Target:
Vampire: The Masquerade – Bloodlines (GOG + Unofficial Patch). 32-bit D3D9
games in general are the goal; 64-bit is a stepping stone.

Read in this order: `docs/ps4/ARCHITECTURE.md` (what carries over, what is
rewritten), `docs/ps4/MILESTONES.md` (a–h, one pass/fail check each, and
phase p between f and g), `docs/ps4/HANDOFF-p.md` (phase p, performance and
audio, before g; plan only so far), `docs/ps4/HANDOFF-f.md` (how f was reached; `HANDOFF-e.md`, `HANDOFF-d.md` and `HANDOFF-c.md` for how e, d and c were reached), `docs/ps4/LOG.md` (every
console run), `docs/ps4/RESEARCH.md`. `refs/` holds read-only reference checkouts.

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
  `docs/ps4/LOG.md`. Say plainly which console behaviour was not tested. Never
  edit a hash or a threshold to make a check pass.
- **Division of labour.** The user launches apps on the PS4 by hand and plays.
  Claude builds, packages, deploys, reads logs and takes screenshots.
  The laptop is the user's only PS4 screen: Claude opens `view.sh` (in the
  background, with the "PS4 Capture" entry's arguments: its `Exec` line in
  `~/.local/share/applications/ps4-capture.desktop`, i.e. the HDMI `--sink`)
  unasked whenever the user is to install, launch or play, and
  reopens it right after every capture that took the stick (`shot.sh`, a
  recording).
- **Git.** The user commits. Do not commit or push unless asked. Never touch `refs/`.

## Environment

| What | Value |
|---|---|
| PS4 Slim | `192.168.8.184`, GoldHEN. FTP `2121` (serves the real root), klog TCP `3232` (plain stream, no history), BinLoader `9090` (only while enabled in GoldHEN) |
| Our netlog | UDP `18194` from the title to this host (orbis-compat's netlog scheme) |
| Console paths | packages `/data/pkg/`, our data `/data/ps4-wine/{prefix,profiles,logs,cache}`, installed app `/user/app/<TITLE_ID>/` |
| Title | `PSWN00001`, content `IV0000-PSWN00001_00-PS4WINE000000000` |
| Host | Kubuntu (Ubuntu 26.04), x86_64. Toolchain at `$OO_PS4_TOOLCHAIN` (default `~/.local/opt/openorbis`); `common.sh` puts `/usr/lib/llvm-18/bin` first in PATH and sets `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` (PkgTool.Core cannot load ICU 78) |
| Screen | USB HDMI capture stick: MacroSilicon MS2109 (USB `345f:2109`) at `/dev/video2` (the laptop webcam is `/dev/video0` and excluded; override with `PS4_CAPTURE_DEV`), MJPEG 1920x1080 up to 60 fps; PS4 at 1080p, HDCP off. No passthrough: the TV stays dark and the laptop is the user's only PS4 screen (`view.sh`). Only one program can read it at a time: close the viewer (its `pgrep -x` PID, never `pkill -f`) before `shot.sh` or any capture. After a stream opens it sends black (7,7,7) for ~1.7 s (~105 frames), so `shot.sh` keeps frame 150 (~3.3 s a shot); an all-7,7,7 frame means no picture or no signal, not a black screen. Short-lived pictures (e: ~10 s, f2: ~2 s): record the launch through the viewer, `view.sh --sink ... --record logs/<ts>-X.mkv` (mpv's `--stream-record`: the one reader shows and records every frame, ~58 fps, ~10 MB/s ≈ 0.6 GB a minute; it stops by itself after `--record-max` s, default 300, and `view.sh --stop-record` ends it at the line while the view goes on; afterwards keep a few seconds around the picture, `ffmpeg -ss A -t D -i X.mkv -c copy`, and delete the rest), then `ffmpeg -ss T -i X.mkv -frames:v 1 F.png`; never a second process in the picture's path (an ffmpeg `tee` into mpv was laggy, and mpv read the pipe as key presses) |

## Scripts (`scripts/ps4/`)

| Script | Does |
|---|---|
| `setup-host.sh` | prints missing apt packages (never sudo); `--install-toolchain` (OpenOrbis v0.5.4, sha256-pinned); `--install-openssl11` (private OpenSSL 1.1 that PkgTool.Core's `pkg_build` needs) |
| `build.sh <target>` | `--check-toolchain`; `compat` (orbis-compat → `build/orbis-compat`), `mesa` (mesa-ps4 RADV, no nix, local clone → `build/mesa-ps4`), `probe` (→ `dist/probe-<id>.pkg`), `probe-test` (host tests, incl. `check_a/b/c_test.sh`), `wine` (fork: host Wine + Orbis PRXs, `--skip-host`), `title` (fork `native/orbis` → `dist/ps4-wine-<id>.pkg`) |
| `pkg.sh --elf X` | ELF → fSELF → `.pkg` in the layout that grants ~4.4 GiB direct memory |
| `deploy.sh FILE` | `.pkg` over FTP to `/data/pkg` (optionally remote-install); `.elf` to BinLoader |
| `logs.sh` | klog (3232) + netlog (18194) merged into `logs/<ts>-<label>.log`; `--expect REGEX --timeout S` gates |
| `shot.sh` | one frame from the capture stick (pinned MJPEG 1920x1080); `--pixel X,Y`, `--expect-rgb` |
| `view.sh` | live view for the user (the "PS4 Capture" menu entry): mpv shows the stick, `pw-loopback` sends its sound to the speakers; holds the stick while open (`--no-audio`, `--sink`, `--device`; `--record FILE` records what it shows, capped by `--record-max`, `--stop-record`; one queued frame, mailbox present) |
| `fbshot.sh` | fetch a title's framebuffer readback (`/data/ps4-wine/shot.raw`) over FTP → PNG; framebuffer, not HDMI |
| `check.sh <a-h, sub-step, pN>` | the milestone's single pass/fail rule; prints the LOG.md line; `--no-shot` / `--fb` for the pixel rules |
| `runtime.sh` | stages the Wine runtime (fork PRXs + host Wine PE modules + nls) under `build/runtime/win/wine` and mirrors it to `/data/ps4-wine/runtime` over FTP (`--prx-only` for a Wine iteration; PRXs get mode 777) |
| `prefix.sh` | `wineboot --init` with the fork's host Wine into `build/prefix` (dosdevices and builtin DLL copies removed, `hello.exe` added), upload to `/data/ps4-wine/prefix` |

The loop for one console run: `logs.sh --label X &` (klog has no history, so
start it first) → `deploy.sh` → `view.sh &` (the user's screen) → the user
installs and launches → `logs.sh --expect` / `check.sh` → close the viewer,
`shot.sh`, reopen the viewer → one line in `docs/ps4/LOG.md`. From milestone c the
Wine runtime and the prefix live on `/data` (`runtime.sh`, `prefix.sh`), so a
Wine fix is `build.sh wine --skip-host` + `runtime.sh --prx-only`, no reinstall;
`/data/ps4-wine/env.txt` (NAME=VALUE lines) changes Wine's environment per run.

## PS4 traps (measured by orbis-ports, nx-on-orbis, playden; see ARCHITECTURE.md)

- The SDK ships musl headers over Sony's FreeBSD-9-derived libc: `struct stat`
  (`mode_t`), pthread attr sizes and `bits/signal.h` are wrong. Build with
  orbis-compat's overlay ahead of the SDK and `-include orbis_prefix.h`.
- A raw `syscall` instruction outside libkernel kills the process; libc
  `syscall()` returns ENOSYS. Relative `open` is EINVAL, `getcwd` ENOSYS,
  `fchdir` crashes, `openat` takes only `AT_FDCWD`. Use absolute paths.
  `dup` is EPERM and `fcntl(F_DUPFD)` EINVAL on every fd; `close`/`dup2` on
  fds 0-2 are EPERM; `pipe`, `socketpair` and `SCM_RIGHTS` fd passing work;
  `shm_open(SHM_ANON)` works. `sceKernelStat` by path returns dev/ino 0,
  `_fstat` on a descriptor returns them. Files under `/data` are root's.
- Default thread stack is 64 KiB (orbis-compat raises it to 2 MiB).
  `timer_create` with SIGEV_THREAD hangs. `sigaltstack` works (libkernel's and raw syscall 53,
  measured in p2) with FreeBSD's `stack_t` `{ss_sp, size_t ss_size, int ss_flags}` and
  `SS_DISABLE` 0x4; the SDK's musl header swaps `ss_size`/`ss_flags` (and has `SS_DISABLE` 2), so
  filled through it the kernel sees `ss_flags=0x10000` and refuses (EINVAL: the old "returns -1").
  The fork's `wine/orbis/include` has had FreeBSD's layout since c; Wine's own call was never logged.
- Returning from `main()` or calling `exit()` (from any module) is reported as
  CE-34878-0: idle forever instead. Writes to fd 1/2 reach only klog. So the
  last launch is still running: close it (PS button, Options, Close
  Application) before reinstalling. Installing over it fails with CE-33237-8
  (klog: `sceLncServiceKillApp ... 0x80aa0003`, measured 2026-11-01).
- Executable memory: `sceKernelAllocateDirectMemory` → map RW → `sceKernelMprotect`
  RWX. Asking for EXEC at map time fails. Page granule 16 KiB.
- Flexible memory (`mmap(MAP_ANON)`, libc malloc) is ~384–440 MiB. Direct
  memory is ~4.4 GiB **only** with the OpenOrbis-samples package layout
  (`sce_module/libc.prx` + `libSceFios2.prx`, `sce_sys/about/right.sprx`,
  SFO `CATEGORY gd`, `SYSTEM_VER 0`, paid `0x3800000000000011`); other layouts
  give 768 MiB or do not boot. `sceKernelReserveVirtualRange`: 16 GiB anywhere,
  512 GiB FIXED at `0x1000000000`.
- Faults come through `sceKernelInstallExceptionHandler` or FreeBSD `sigaction`
  (FreeBSD values and layouts: the fork's `wine/orbis/include`): the PS5's frame,
  mcontext at ucontext+64 (rip +224), FXSAVE +320, FS base +1152, cs64 `0x43`;
  `sysarch` 128–131 get/set FS and GS; a far jump to `0x33` runs 32-bit code.
- `sceSystemServiceLoadExec(path, args)` restarts the title; the new process
  gets the arguments from `argv[0]` on (no program name). An app PRX (`/app0`
  or `/data`, mode 777) loads and `sceKernelDlsym` resolves its exports; the
  loader runs neither its constructors nor `module_start`: link it `-pie
  --export-dynamic -e module_start` with the SDK's `link.x`, a global
  `module_start` and a writable module-param block (no crtlib.o), and call
  `module_start` yourself. One app PRX imports from another through the loader
  (functions and data, bound at load, measured in d1) if the exporter is
  already loaded (load it first: d1's "the loader does not load a NEEDED app
  module itself" came from a name check that never matched, see HANDOFF-e) and the
  names agree: exporter linked `-soname NAME.so` and converted with
  `create-fself -libname=NAME`, importer linked against a stub with that soname
  (`tools/orbis_import_stub.py`). libkernel also exports `dlopen`/`dlsym`/`dlclose`,
  and create-fself gives an import to the first NEEDED library exporting its name
  (libkernel first): import those from ntdll as `__wrap_` names. A PT_LOAD
  that starts mid-page is ENOEXEC (`--no-rosegment`, 16 KiB pages). Each PRX
  has its own musl: `environ` and `stderr` are per module.
- `dup` is refused, but passing a descriptor to the process itself with
  SCM_RIGHTS duplicates it (shared offset and flags): `__wrap_dup` does that
  (`wine/orbis/pw_wine_dup_orbis.c`); the server's `set_queue_fd` needs it.
- `realpath()` fails for every path (musl reads `/proc/self/fd/N` with
  `readlink`, an ENOSYS stub): the cwd emulation's lexical one on Orbis. Every
  module that opens files by Wine's `dosdevices/c:` names links its own cwd
  emulation (the `c:` link is virtual). Private read-only `mmap` of a `/data`
  file works.
- `libc.a` has a 16-bit `wchar_t` (`wmem*` wrong for 4 bytes), `secure_getenv`
  returns NULL. klog (`sceKernelDebugOutText`) costs 8–15 ms a line and blocks
  when nothing drains it: netlog for volume, klog for startup and fatal lines.
- `libc.a` is musl with the syscall layer replaced: 134 of its functions only set
  ENOSYS (`epoll_*`, `ppoll`, `fchdir`, `readlink`, `symlink`, `link`, the `*at`
  family, `umask`, `uname`, `times`, `setsid`, `sched_*affinity`, `getrandom`, xattr;
  the fork's `tools/orbis_libc_stubs.py` lists them). Configure's link tests take
  them for real, so `build_wine_orbis.sh` declares every one Wine checks for absent
  and fails when a `HAVE_*` names one. libkernel has `kqueue`/`kevent`/`poll`, no epoll.
- Vulkan (RADV, "PlayStation 4 Liverpool", GFX7, Vulkan 1.3): a submission
  must fit 2 MiB (524288 dwords) or the GPU hangs; `VK_EXT_conditional_rendering`
  and `VK_KHR_draw_indirect_count` hang the GPU; about one submit in 1200
  stalls; surface formats are RGBA only (BGRA swaps red and blue); arena size
  via `ORBIS_ARENA_MIB`. Vulkan titles link `libvulkan_radeon.a` with
  `--whole-archive` plus the kit's vkloader thunks.
- Compile with `-march=btver2 -femulated-tls -fno-omit-frame-pointer` (no emutls
  runtime in the SDK; Wine's Unix side needs none). Cpuset `0x3f`: 6 Jaguar
  cores at 1.59 GHz (Slim); pinning to cores 6/7 returns `0x80020001`.

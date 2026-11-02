# Third-party software and reference code

ps4-wine is licensed under GPL-3.0 (`LICENSE`). Code under
`third_party/prospero-win` (a submodule of our fork, created in milestone c)
and patches under `upstream/` stay LGPL-2.1-or-later so they can go back to
prospero-win; see `CLAUDE.md` for the rules.

The checkouts under `refs/` are study material and build inputs. They are not
tracked by this repo. When a file, function or script in this repo is derived
from one of them, the derived code carries a comment

    From: <repo> <path> @ <commit> (<licence>)

and a row in the "Derived code" table below.

## Host-side tools (not shipped)

| Tool | Version | Licence | Why |
|---|---|---|---|
| OpenSSL, private copy under `~/.local/opt/openssl-1.1` | 1.1.1w, sha256 `cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8` | OpenSSL/SSLeay | PkgTool.Core (.NET Core 3.0) `pkg_build` needs OpenSSL 1.x; Ubuntu 26.04 has only 3.x. Used by `pkgtool()` in `common.sh` only (`setup-host.sh --install-openssl11`) |

## Reference repositories (`refs/`)

| Repository | Commit pinned here | Licence | What we use it for |
|---|---|---|---|
| [mpereiraesaa/prospero-win](https://github.com/mpereiraesaa/prospero-win) | `0e7b6b4` (2026-10-29) | LGPL-2.1-or-later | The design we port: Wine in-process, IA-32 translator, native WoW64, Vulkan batching, user driver, Wine patch series |
| [orbis-ports/mesa-ps4](https://github.com/orbis-ports/mesa-ps4) | `1a59cc1` (2026-09-18) | MIT (Mesa) | RADV for Liverpool/Gladius with the no-DRM winsys and the sceVideoOut WSI (`src/vulkan/wsi/wsi_orbis.c`) |
| [orbis-ports/orbis-compat](https://github.com/orbis-ports/orbis-compat) | `6922a7b` (`6922a7b6f4291a28edd239f1a4db50ed7aa00359`, 2026-09-21, archived; built from a clone under `build/src` with `patches/orbis-compat/*.patch`, MIT, by `build.sh compat`) | MIT; `cmake/orbis-tls.ld` GPL-3.0-only; `include/sys/ioccom.h` BSD-3 | libc/pthread corrections over the OpenOrbis SDK, `orbis_jit` API, UDP netlog, `ps4_app` log tee, packaging recipe |
| [orbis-ports/ps4-mesa-docs](https://github.com/orbis-ports/ps4-mesa-docs) | `deb1903` (2026-09-19) | (docs) | Handoff notes, CTS results, radeon_info dumps, memory and GPU traps |
| [orbis-ports/orbis-porting-kit](https://github.com/orbis-ports/orbis-porting-kit) | `213b0c3` (2026-09-21, archived) | MIT; `cmake/orbis-tls.ld` GPL-3.0-only | `cmake/orbis.ini.in` (meson cross template for `build.sh mesa`), `orbis-tls.ld`, `make-pkg.sh`, `deploy.sh`, `logs.sh`, `log-receiver.py`, the Vulkan loader shim (`vkloader/`), `cmake/ps4-openorbis.cmake`. mesa-ps4's handoff names kit `0aff500`; HEAD built mesa-ps4 `1a59cc1` cleanly |
| [alechurri/nx-on-orbis](https://github.com/alechurri/nx-on-orbis) | `11b2c65` (2026-10-07) | GPL-3.0-or-later | PS4 Pro port of Eden: memory/fault/JIT findings, the package layout that grants ~4.4 GiB, `probe/probe.c`, `package-eden.sh`. **Never copied into LGPL code** |
| [OpenOrbis/OpenOrbis-PS4-Toolchain](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain) | `0a1aaf9` (v0.5.4+2) | GPL-3.0 (link.x, `include/orbis`, crtlib.o, create-fself/create-gp4); LGPL-3.0 (PkgTool/LibOrbisPkg); MIT (musl crt); Apache-2.0 w/ LLVM exception (libc++) | The toolchain: clang target, `link.x`, `create-fself`, `create-gp4`, `PkgTool.Core`, sample `sce_module`/`right.sprx` files |
| [leolobato/playden-ps5](https://github.com/leolobato/playden-ps5) | `7d688b3` (2026-10-29) | GPL-3.0-or-later | Conventions: FTP deploy with verify-and-rename, log collection, `THIRD_PARTY_NOTICES.md` format, prospero-win profile usage |

## Derived code in this repo

| File in ps4-wine | Derived from | Licence of the source | Notes |
|---|---|---|---|
| `scripts/ps4/pkg.sh` | nx-on-orbis `package-eden.sh` @ `11b2c65`; OpenOrbis `samples/hello_world/Makefile` @ `0a1aaf9` | GPL-3.0-or-later; GPL-3.0 | Package layout and SFO entries (the layout that grants ~4.4 GiB direct memory) |
| `scripts/ps4/build.sh` (`build_mesa`) | mesa-ps4 `build-support/orbis/build.sh` @ `1a59cc1` | MIT | Cross-file substitution, meson option set, build id, sysconf check; without nix, out of the reference tree |
| `probes/probe.c` | nx-on-orbis `probe/probe.c` @ `11b2c65` (stage harness, memory ladder, VA/alias, JIT, fault resume, range_free); nx-on-orbis `frontend/menu/rom_menu.cpp` @ `11b2c65` (VideoOut constants and setup) | GPL-3.0-or-later | Milestone a probe. The marked-MXCSR frame check follows the idea of prospero-win patch 0883 (no code taken) |
| `probes/probe_sce.h` | nx-on-orbis `probe/probe.c` @ `11b2c65` lines 49-68 | GPL-3.0-or-later | libkernel declarations by asm label |
| `probes/probe_netlog.c` | orbis-compat `optional/orbis_netlog.cpp` @ `6922a7b` | MIT | UDP netlog, rewritten in C |
| `probes/triangle.c` | orbis-porting-kit `examples/triangle/triangle.c` @ `213b0c3` | MIT | Milestone b title: instance, headless surface, swapchain, render pass, pipeline and present sequence. Shaders are ours |
| `scripts/ps4/build.sh` (`build_triangle`) | orbis-porting-kit `cmake/ps4-openorbis.cmake` @ `213b0c3`; mesa-ps4 `build-support/orbis/tools/linkprobe.sh` @ `1a59cc1` | MIT | The title link line (orbis-tls.ld, --no-rosegment, whole-archive overlay + libc16 objects, whole-archive RADV) |
| `scripts/ps4/runtime.sh` | prospero-win `tools/package_release.sh` @ `0e7b6b4` | LGPL-2.1-or-later | The `win/wine/lib/wine/{x86_64-unix,*-windows}` + `share/wine/nls` layout and the host-Wine exclusions |
| `scripts/ps4/prefix.sh` | prospero-win `tools/pw_prefix.py` @ `0e7b6b4` | LGPL-2.1-or-later | What is stripped from a prefix before the upload and the size verification |
| `tests/fixtures/c-*.log` | the fork's `native/orbis/wine64_main_orbis.c` record format | LGPL-2.1-or-later | Synthetic logs for `check.sh c` |

## The fork: `third_party/prospero-win` (submodule, branch `orbis`)

Our fork of [mpereiraesaa/prospero-win](https://github.com/mpereiraesaa/prospero-win) at
[Maxikozie/prospero-win](https://github.com/Maxikozie/prospero-win), LGPL-2.1-or-later, branched from
`0e7b6b4`. Everything under it follows the upstream boundary in `CLAUDE.md`: its own
`THIRD_PARTY.md` lists what the PS4 title and the Orbis headers restate (FreeBSD 9 ABI facts,
BSD-2-Clause; orbis-compat facts, MIT) and that `eboot.bin` is linked with the OpenOrbis
`link.x`/`crt1.o` (GPL-3.0), which makes the shipped title GPL-3 as the PS5's is.

## Shipped in a package (to be filled from milestone a on)

Every `.pkg` we build carries files that are not ours. Record them here with
their licence texts under `LICENSES/` before the first package leaves this
machine for anyone else:

| Component | Version | Licence | Source |
|---|---|---|---|
| Wine's logo, `assets/icon0.png`: `dlls/user32/resources/oic_winlogo.ico`'s 256x256 PNG entry (stream 7), scaled to 448x448 and centred on white 512x512, rgb24 (the ffmpeg line is in `scripts/ps4/pkg.sh`) | Wine `490f6d5` | LGPL-2.1-or-later | `sce_sys/icon0.png` of every package `pkg.sh` builds (title, probe, triangle) unless `--icon` names another |
| OpenOrbis `sce_module/libc.prx`, `libSceFios2.prx`, `sce_sys/about/right.sprx` | v0.5.4 | GPL-3.0 (OpenOrbis samples) | toolchain release asset `toolchain-llvm-18.tar.gz`, sha256 `3c7cd5bb593ca74fa1c13fd59f3938dc0fc07985167f7275063019e63abe4526` |
| OpenOrbis `crt1.o`, `link.x`, `libc.a` (musl), `libc++` | v0.5.4 | MIT (musl crt), GPL-3.0 (`link.x`), Apache-2.0 with LLVM exception (libc++) | linked into the probe's `eboot.bin` |
| orbis-compat `liborbis-compat.a` members, `crt/crtlib.o` (+ `patches/orbis-compat/0001` from p6 on) | `6922a7b` | MIT | linked into the probe and `probe_mod.prx` |
| Mesa RADV `libvulkan_radeon.a` (mesa-ps4) + `patches/mesa-ps4/0001` | `1a59cc1` | MIT | linked into the triangle's `eboot.bin` (milestone b) |
| zlib (Mesa's meson wrap) | 1.3.1 | Zlib | linked into the triangle's `eboot.bin` |
| Mesa RADV `libvulkan_radeon.a` (mesa-ps4, built `-femulated-tls` by `build.sh mesa --prx`) + `patches/mesa-ps4/0001`, `0002` (`ORBIS_WSI_SHOT`), and its zlib 1.3.1 | `1a59cc1` | MIT; Zlib | linked `--whole-archive` into `libvulkan.prx` (milestone e), uploaded to `/data/ps4-wine/runtime` by `runtime.sh` |
| orbis-porting-kit `vkloader/vkloader.c` + thunks generated by its `gen.py` | `213b0c3` | MIT | linked into the triangle's `eboot.bin` |
| Wine (the pinned `490f6d5d` + the fork's series): `ntdll.prx`, `wineserver.prx`, `win32u.prx`, `x86_64-windows/*.dll`, `i386-windows/*.dll`, `share/wine/nls` | `490f6d5d` | LGPL-2.1-or-later | uploaded to `/data/ps4-wine/runtime` by `runtime.sh` (milestone c); not in a `.pkg` yet |
| orbis-compat `liborbis-compat.a` members + `libc16/*.o` + `patches/orbis-compat/0001` (caller-set thread stacks kept, phase p6); OpenOrbis `libc.a`, `libc++.a`, `libkernel` stubs | `6922a7b`; v0.5.4 | MIT; MIT (musl), Apache-2.0 w/ LLVM exception, GPL-3.0 (`link.x`, `crt1.o`) | linked into the Wine PRXs and the milestone c title (`build/elf/ps4-wine-<id>.elf`) |
| orbis-compat `liborbis-compat.a` (whole archive) + `libc16/*.o` (+ `patches/orbis-compat/0001` from p6 on) | `6922a7b` | MIT | linked into the triangle's `eboot.bin` |
| (Wine, FreeType, DXVK, LLVM runtimes: added when they are first packaged) | | | |

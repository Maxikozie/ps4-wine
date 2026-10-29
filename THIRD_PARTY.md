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

## Reference repositories (`refs/`)

| Repository | Commit pinned here | Licence | What we use it for |
|---|---|---|---|
| [mpereiraesaa/prospero-win](https://github.com/mpereiraesaa/prospero-win) | `0e7b6b4` (2026-10-29) | LGPL-2.1-or-later | The design we port: Wine in-process, IA-32 translator, native WoW64, Vulkan batching, user driver, Wine patch series |
| [orbis-ports/mesa-ps4](https://github.com/orbis-ports/mesa-ps4) | `1a59cc1` (2026-09-18) | MIT (Mesa) | RADV for Liverpool/Gladius with the no-DRM winsys and the sceVideoOut WSI (`src/vulkan/wsi/wsi_orbis.c`) |
| [orbis-ports/orbis-compat](https://github.com/orbis-ports/orbis-compat) | `6922a7b` (2026-09-21, archived) | MIT; `cmake/orbis-tls.ld` GPL-3.0-only; `include/sys/ioccom.h` BSD-3 | libc/pthread corrections over the OpenOrbis SDK, `orbis_jit` API, UDP netlog, `ps4_app` log tee, packaging recipe |
| [orbis-ports/ps4-mesa-docs](https://github.com/orbis-ports/ps4-mesa-docs) | `deb1903` (2026-09-19) | (docs) | Handoff notes, CTS results, radeon_info dumps, memory and GPU traps |
| [orbis-ports/orbis-porting-kit](https://github.com/orbis-ports/orbis-porting-kit) | to clone in milestone a (archived) | MIT (see its LICENSING) | `make-pkg.sh`, `deploy.sh`, `logs.sh`, `log-receiver.py`, the Vulkan loader shim (`vkloader/`), `cmake/ps4-openorbis.cmake`, `cmake/orbis.ini.in` |
| [orbis-ports/orbsdk](https://github.com/orbis-ports/orbsdk) | to clone in milestone a | (check) | Successor of orbis-compat + the kit: one owned sysroot |
| [alechurri/nx-on-orbis](https://github.com/alechurri/nx-on-orbis) | `11b2c65` (2026-10-07) | GPL-3.0-or-later | PS4 Pro port of Eden: memory/fault/JIT findings, the package layout that grants ~4.4 GiB, `probe/probe.c`, `package-eden.sh`. **Never copied into LGPL code** |
| [OpenOrbis/OpenOrbis-PS4-Toolchain](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain) | `0a1aaf9` (v0.5.4+2) | GPL-3.0 (link.x, `include/orbis`, crtlib.o, create-fself/create-gp4); LGPL-3.0 (PkgTool/LibOrbisPkg); MIT (musl crt); Apache-2.0 w/ LLVM exception (libc++) | The toolchain: clang target, `link.x`, `create-fself`, `create-gp4`, `PkgTool.Core`, sample `sce_module`/`right.sprx` files |
| [leolobato/playden-ps5](https://github.com/leolobato/playden-ps5) | `7d688b3` (2026-10-29) | GPL-3.0-or-later | Conventions: FTP deploy with verify-and-rename, log collection, `THIRD_PARTY_NOTICES.md` format, prospero-win profile usage |

## Derived code in this repo

| File in ps4-wine | Derived from | Licence of the source | Notes |
|---|---|---|---|
| `scripts/ps4/pkg.sh` | nx-on-orbis `package-eden.sh` @ `11b2c65`; OpenOrbis `samples/hello_world/Makefile` @ `0a1aaf9` | GPL-3.0-or-later; GPL-3.0 | Package layout and SFO entries (the layout that grants ~4.4 GiB direct memory) |

## Shipped in a package (to be filled from milestone a on)

Every `.pkg` we build carries files that are not ours. Record them here with
their licence texts under `LICENSES/` before the first package leaves this
machine for anyone else:

| Component | Version | Licence | Source |
|---|---|---|---|
| OpenOrbis `sce_module/libc.prx`, `libSceFios2.prx`, `sce_sys/about/right.sprx` | v0.5.4 | GPL-3.0 (OpenOrbis samples) | toolchain release asset |
| (Wine, FreeType, Mesa, DXVK, orbis-compat, LLVM runtimes: added when they are first packaged) | | | |

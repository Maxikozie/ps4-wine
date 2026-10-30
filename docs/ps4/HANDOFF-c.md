# Hand-off: milestone c (Wine core boots a 64-bit console EXE)

Written 2026-10-30 03:30 after ten console runs. Read `CLAUDE.md`, then this, then
`docs/ps4/LOG.md` (one line per run) and the plan at the top of `MILESTONES.md` c notes.

## Status

**Not passed.** The check line still reads `server=none exit=timeout`. Everything up to the
in-process wineserver's client handshake works on the console: the title, the PRX recipe,
ntdll.prx (loads, `__wine_main` runs, direct memory and the Wine heap in use, 512 GiB high
area granted), the environment and stderr hand-over, the exit hook, wineserver.prx (loaded by
ntdll, its startup finished: directories, anonymous mappings in shared memory, registry).

**Exact blocker (run 10, `logs/20261030-032005-c.log`):** ntdll prints the connect-time lines
(`wine-ps5: shared event/semaphore backend: off`, `shared mutex backend: off`, `server requests
on client threads: off`, `immediate mutex calls: off`, all from `connect_inprocess_server`,
`dlls/ntdll/unix/server.c:1935`) and then never reaches the `wine startup: server connected`
mark. Between the two: `server_connect()` returns the client socket, then
`server_init_process` blocks in `wine_server_receive_fd(&version)` (server.c:2226), waiting
for the server thread to hand over the request descriptor. The server's main loop runs on a
pthread started at the end of `start_inprocess_server` (`server/main.c`); it was built on the
kqueue path (`sys/event.h` exists in `wine/orbis/include`), and nothing has shown that
`kevent` wakes for an AF_UNIX socket pair on this kernel. `SCM_RIGHTS` passing itself works
(measured from the title, run 10).

## The runs (details in LOG.md)

| # | time | change | proved | failed |
|---|---|---|---|---|
| 1 | 02:41 | first launch | netlog, `pipe()`, PRX recipe (`-pie --export-dynamic -e module_start` + `link.x`, no crtlib.o): module loads, ctor runs via `module_start`, `sceKernelDlsym` resolves | `ntdll.prx` ENOEXEC; `dup2` onto 1/2 refused |
| 2 | 02:51 | writable module-param block, `--no-rosegment` | ntdll loads (3 page-aligned segments), hook, sink, `__wine_main` runs; `PT_TLS` module loads | Wine saw no environment (per-PRX musl `environ`) |
| 3 | 02:57 | `pw_wine_setenv` export + loader replay | env reaches Wine; `init_paths`, `virtual_init`, dmem, heap, 512 GiB high area | server `fatal_error` "not owned by you" → real `exit` → CE-34878-0 |
| 4 | 03:01 | patch 1020, exit hook forwarded to loaded modules | server start reached; the hook catches a module's exit | server's message lost (fd 2 only reaches klog) |
| 5 | 03:05 | `--wrap=write,writev,_write,_writev` | module stderr arrives as `WINESERVER` records | "chdir did not end up in": `lstat` gave dev/ino 0 |
| 6 | 03:07 | patch 1030 (report, continue) | path stat has no identity, fd stat does | SIGSEGV addr 0 in wineserver.prx |
| 7 | 03:13 | fork stat family (open+`_fstat` fallback), raw bytes dumped | identity check passes | same fault, now named: `release_object` |
| 8 | 03:16 | frame-pointer backtrace in the title | fault is `release_object(NULL)` in `init_directories` | |
| 9 | 03:22 | patch 1040 (report, continue) | shm_open(SHM_ANON) works; nls mapping fails with EPERM | client never connects (closed at 73 s) |
| 10 | 03:29 | fd probe in the title, `--wrap=dup` | `dup` EPERM, `F_DUPFD` EINVAL, `SCM_RIGHTS` passes fds; files reopened by path | watchdog at 180 s, `server=none` |

## PS4 facts found in c (all measured on the console)

- A PRX image is refused with ENOEXEC (0x80020008) when a large PT_LOAD starts mid-page: a
  read-only 24-byte module-param block becomes its own segment and `.data/.bss` follow it by
  0x20 bytes. Writable module-param block + `--no-rosegment` + 16 KiB max page gives three
  page-aligned segments; that loads. A separate mid-page read-only segment in a tiny module
  loaded anyway (run 1), so it is the data segment that matters. A module with a `PT_TLS`
  segment loads and runs (`pw_probe_tls.prx`).
- The loader never runs a module's constructors or its `module_start`; `sceKernelDlsym`
  resolves app-PRX exports; `sceKernelLoadStartModule` returns the same handle for a
  module already loaded.
- Each PRX links its own static musl: `setenv` in one image is invisible in another, and so
  is `stderr`. `dup()` is EPERM and `fcntl(F_DUPFD)` EINVAL on every descriptor kind;
  `close(1)`, `close(2)` and `dup2` onto 1/2 are EPERM. `pipe()` works. `socketpair` +
  `sendmsg`/`recvmsg` with `SCM_RIGHTS` passes descriptors. `shm_open(SHM_ANON)` + `ftruncate`
  works (Wine's anonymous mappings live there).
- `sceKernelStat` by path returns dev/ino 0 (raw bytes in LOG.md run 7: mode at 0x08, times
  at 0x18/0x28/0x38, size 0x48, blksize 0x4000 at 0x58); `_fstat` on a descriptor returns
  them. Files under `/data` belong to root and the process is not root (unix-owner checks
  fail). `/data/ps4-wine` is created by the title with mode 0777.
- A title that calls `exit()` (from any module) is SIGSYS-killed and reported as CE-34878-0.
  Writes to fd 1/2 reach only the kernel log, which the host's klog stream loses under
  GoldHEN's hook spam.
- musl's `sysconf(_SC_PAGESIZE)` is 16384 (the libc.a was built for the 16 KiB page).
- The kernel granted a 512 GiB `sceKernelReserveVirtualRange` FIXED|NO_OVERWRITE at
  `0x1000000000` (the a-probe measured 16 GiB anywhere).
- `lftp mirror --only-newer` trusts the console clock and skips changed files; GoldHEN's
  remote package installer (12800) does not answer: install from the Package Installer.

## Fork additions (branch `orbis`, all uncommitted)

Real fixes:
- `tools/widen_console_gates.py` + the 46 rewritten 0xxx patches: `__PROSPERO__` gates widened
  to `__PROSPERO__ || __ORBIS__` (0883/0903 PS5-only; context lines only there). Series
  range 0100–1499 in `build_wine_ps5.sh`, `build_host_wine.sh`, `test_build_wine_ps5.py`.
- `wine/orbis/include/`: FreeBSD-ABI headers over the SDK's musl ones (`bits/signal.h`,
  `signal.h`, `sys/ucontext.h` via bits, `machine/{trap,segments,sysarch}.h`, `sys/thr.h`,
  `sys/{socket,un,event,mount,statfs,vfs,filio,sockio,ioctl,sysctl,resource,cdio}.h`,
  `netinet/{in,tcp}.h`, `dev/acpica/acpiio.h`, `pthread_np.h`).
- `wine/orbis/pw_wine_exit_orbis.c` (`--wrap=exit,_exit,abort` → title hook, forwarded by
  the loader shim to every loaded module), `pw_wine_env_orbis.c` (`pw_wine_setenv` export,
  environment replay on load), `pw_wine_stdio_orbis.c` (`--wrap=write,writev,_write,_writev`
  → `PW_ORBIS_STDOUT_FD`/`STDERR_FD`), `pw_wine_compat_orbis.c` (`thr_self`, `ppoll`, the
  stat family with open+`_fstat` identity fallback, `__wrap_dup` = F_DUPFD then reopen by
  path through `pw_cwd_fd_path`).
- `wine/ps5/pw_wine_dmem_ps5.c` `__ORBIS__` branch (`sceKernelAllocateDirectMemory`, WB_ONION);
  `pw_wine_dl.c` `__ORBIS__` block (env + exit hook replay); small `__ORBIS__` fixes in
  `pw_wine_compat{,_libc}.c`, `pw_wine_cwd_libc.c`, `pw_wine_dl_libc.c` (RTLD_SELF).
- `tools/orbis-clang`, `tools/build_wine_orbis.sh`, `tools/orbis_prx_report.py`,
  `tools/gen_prx_descriptor.py --orbis` (global `module_start`, writable module-param block),
  `tools/build_native_orbis.sh`, `native/orbis/wine64_main_orbis.c` (title),
  `native/orbis/orbislog/`, `native/orbis/pw_probe_mod.c`, `tests/wine_hello64.c` + host
  tests (`test_pw_wine_{dmem_orbis,exit_orbis,stdio_orbis}`, `test_wine_hello64.py`).
- Patch 1010 (standard handles from `PW_ORBIS_STDOUT_FD`/`STDERR_FD`), 1020 (no unix-owner
  checks on Orbis).
- `build_wine_runtime.sh`/`build_host_wine.sh`: `PROSPERO_WINE_CONFIGURE_EXTRA` (headless host
  Wine); host stamp ignores 1000+ patches.

Diagnostic, to remove once the cause is fixed:
- **Patch 1030**: reports the server-dir dev/ino mismatch instead of `fatal_error`. The stat
  family makes the check pass now; drop the patch once a run confirms it stays silent.
- **Patch 1040**: reports a failed startup mapping and continues. The nls mapping fails
  because of `dup`; once `__wrap_dup` is seen to cover it (no "nls mapping failed" line),
  restore the plain `release_object` calls.
- The title's `probe_pipe`, `probe_fds`, `probe_module` and the raw `sceKernelStat` dump
  in the stat shim are measurements; keep until the LOG records them, then trim.
- `__wrap_dup`'s reopen-by-path is a stop-gap: it cannot cover sockets, pipes or shared
  memory, and the server's `dup_fd_object` wants a real duplicate. A proper answer is a
  server-side change that shares the descriptor (refcount) instead of duplicating it on Orbis.

## Iteration loop

```
scripts/ps4/build.sh wine --skip-host      # Orbis PRXs (full reconfigure when a patch changed, ~10 min; else ~2 min)
scripts/ps4/runtime.sh --prx-only          # upload ntdll/wineserver/probe PRXs (sizes verified)
scripts/ps4/build.sh title                 # only when native/orbis changed → dist/ps4-wine-<id>.pkg
scripts/ps4/deploy.sh dist/ps4-wine-*.pkg  # → /data/pkg; the user installs from GoldHEN > Package Installer (reinstall!)
scripts/ps4/logs.sh --label c --expect 'PS4WINE c ' --timeout 7200 &
# user launches; then:
scripts/ps4/check.sh c                     # prints the LOG.md line
```
A title change needs a reinstall; a PRX change does not. `scripts/ps4/prefix.sh` makes and
uploads the prefix (done; `/data/ps4-wine/prefix` holds `drive_c/hello.exe`).
Knobs: `/data/ps4-wine/env.txt` (NAME=VALUE lines, applied after the title's defaults:
`WINE_PS5_SERVER_DIRECT=0`, `WINE_PS5_MUTEX_SHARED=0`, `WINE_PS5_SYNC_SHARED=0`,
`WINEDEBUG=err+all,+loaddll,+process`); `/data/ps4-wine/dev.conf` (`DEV_SERVER=`, `DEV_PORT=`
for the netlog target; the build-time default is this host's address on the route).
Fork tests: `PATH=/usr/lib/llvm-18/bin:$PATH make test` in the fork; repo: `build.sh probe-test`.
Symbolize: `llvm-symbolizer-18 --obj=third_party/prospero-win/.deps/wine-orbis/prx/<mod>.shared.elf 0x<offset>`;
the title's fault report prints `module+offset` per frame.

## Next hypotheses, in order

1. **The server's main loop never wakes on kqueue.** Build with the poll path:
   `ac_cv_header_sys_event_h=no ac_cv_func_kqueue=no` in `build_wine_orbis.sh`'s
   `configure_args` (and drop `wine/orbis/include/sys/event.h` if that is simpler). Add two
   Orbis stderr lines in `server/request.c`: on entering `main_loop` and in
   `receive_inprocess_client`.
2. If the loop runs but no client arrives: the client's `sendmsg` to `client_channel`
   (`request.c:898`) or the server's `recvmsg` of it; check `msg_controllen` handling
   (FreeBSD 12-byte `cmsghdr`, `CMSG_SPACE(int)` = 24, measured working from the title).
3. If the handshake completes and `server connected` prints: expect `dup`-dependent paths
   next (`dup_fd_object` on sockets/pipes), then the PE load (`mmap` private file views →
   `pread` fallback), then signals (`sigaltstack` returned -1 in a; no alt stack).
4. `WINE_PS5_SERVER_DIRECT=1` only after the stock path connects.

## Uncommitted work

Repo (`main`): `.gitmodules` + the `third_party/prospero-win` gitlink (staged), `CLAUDE.md`,
`THIRD_PARTY.md`, `docs/ps4/{ARCHITECTURE,MILESTONES,LOG,HANDOFF-c}.md`,
`scripts/ps4/{build,pkg,setup-host}.sh`, new `scripts/ps4/{runtime,prefix}.sh`,
`tests/check_c_test.sh`, `tests/fixtures/c-*.log`.
Fork (`orbis`, no commits yet, branch not pushed): everything listed under "Fork additions",
plus `Makefile`, `THIRD_PARTY.md`, the three test files touched, `tools/build_wine_ps5.sh`,
`tools/build_wine_runtime.sh`, `tools/build_host_wine.sh`. Build outputs under `.deps/` and
`build/` are ignored.

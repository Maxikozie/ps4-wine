# Hand-off: milestone c (Wine core boots a 64-bit console EXE)

Written 2026-10-30 03:30 after ten console runs; revised through 04:30 (runs 11–15, pass).
Read `CLAUDE.md`, then this, then `docs/ps4/LOG.md` (one line per run) and `MILESTONES.md`
(c notes carry the lessons; d is next).

## Status

**PASSED 2026-10-30 04:26 (run 15):** `PS4WINE c hello.exe stdout="Hello from PE64"
server=inprocess exit=0`. Fifteen console runs from the first launch at 02:42. The chain on
the console: title → ntdll.prx (direct memory, heap, 512 GiB high area, environment and
stderr hand-over, exit hook) → wineserver.prx (in-process, kqueue loop, client socket over
an AF_UNIX channel, request/reply/wait descriptors as kernel pipes) → PE loader (hello.exe
native, ntdll/kernelbase/kernel32/msvcrt builtin from the prefix's system32 files) → stdout
through the title's sink → exit 0 through the hook. Read `docs/ps4/LOG.md` for every run.

**Before milestone d, in the fork:** drop the diagnostic patches 1030 and 1040 (both silent
in runs 13–15), reduce 1050/1060/1070 to what stays (the `WINE_ORBIS_POLL` knob only if the
kqueue path ever misbehaves; `init_thread`'s blocking fallback is dead code with kernel
pipes but harmless; the handshake/request stderr lines go). Open console facts to carry:
`dup` and `F_DUPFD` refused (reopen-by-path wrap covers files only; the server's
`dup_fd_object` on sockets/pipes needs a refcount answer); `O_NONBLOCK` impossible on
AF_UNIX sockets (`server/sock.c` for Winsock: per-call `MSG_DONTWAIT`); `sigaltstack` -1
(no alternate stack for Wine's fault handlers; nothing faulted under Wine yet);
`WINE_PS5_SERVER_DIRECT=1`, shared mutex/sync backends untested; `times()`,
`setsid()`, `setpgid()` are ENOSYS stubs still linked (results unread or unreached).

### History of the blocker (runs 1–14)

**Not passed.** The check line still reads `server=none exit=timeout`. Run 11 (04:02) completed
the in-process client handshake for the first time (kqueue loop, client socket passed,
request fd 32 received with protocol 961). Run 12 (04:07) named the stall: **`fcntl(F_SETFL,
O_NONBLOCK)` on a passed socket-pair end returns EACCES** on this kernel, so `init_thread`
failed, the server killed the first thread without a reply and the client waited on its own
reply pipe. Run 13 (04:14) got past it with patch 1070 and printed **`server connected`**
for the first time; FIONBIO is refused like F_SETFL on AF_UNIX sockets, so nothing makes a
socket non-blocking on this kernel. Run 14 (04:18) with the kernel's `pipe()` for Wine's
pipes (the knob, now the Orbis default in `pw_wine_compat_libc.c`): `O_NONBLOCK` works on
kernel pipes, the `getauxval` fault (musl walks a NULL aux vector in a PRX; shimmed) is
gone, `hello.exe` and the builtin `ntdll.dll` were mapped, and the PE loader stopped at
`could not load kernel32.dll, status c0000135`: `prefix.sh` had deleted every DLL/EXE from
`system32`/`syswow64`, and Wine's PE loader maps a builtin only when its file exists there.
Run 15: prefix rebuilt with the files (340 MB, uploading 04:22) + kernel pipes by default. Everything up to the handshake works on the console: the title, the PRX recipe,
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
pthread started at the end of `start_inprocess_server` (`server/main.c`). `SCM_RIGHTS`
passing itself works (measured from the title, run 10).

**Correction (host, 04:00):** the server was *not* on the kqueue path. `server/fd.c` takes
epoll first when configure finds `sys/epoll.h` and `epoll_create`, and the SDK's `libc.a`
has both: musl's header and a stub that sets ENOSYS and returns -1 (disassembled). So
`epoll_fd` was -1, `main_loop_epoll` returned at once and all ten runs sat in Wine's plain
`poll()` fallback (libkernel's `poll`), unseen, because neither side prints anything
between the connect and the request fd. Whether the server thread reached that loop, and
whether `poll` ever reported the master socket, was never measured. Run 11 measures it
(patch 1050) and gets the kqueue path for the first time (configure fix); `WINE_ORBIS_POLL=1`
in `env.txt` puts the same build back on `poll` for a second launch.

The same disassembly found 134 ENOSYS stubs in `libc.a` (`tools/orbis_libc_stubs.py` in the
fork lists them). Configure had taken nine for real: `epoll_create`, `sched_setaffinity`,
`sched_getcpu`, `getrandom`, `sysinfo`, `memfd_create`, `process_vm_readv/writev`,
`futimesat`; all declared absent now and the build fails if a `HAVE_*` names a stub. Linked
into the PRXs and called unchecked: `uname` (ntdll's version string; shimmed in
`pw_wine_compat_orbis.c`), `times` (thread times fallback, result unread; left), `setsid`,
`setpgid` (process spawn paths, not reached). `umask` was already the PS5 compat's.

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

## Fork additions (branch `orbis`; committed as abee8ea, runs 11–15 uncommitted)

Runs 11–15 (uncommitted): `tools/orbis_libc_stubs.py` + `tests/test_orbis_libc_stubs.py` (in
`make test`), `build_wine_orbis.sh` configure declarations + post-configure stub check and
`--wrap=fcntl --wrap=pipe`, `pw_wine_compat_orbis.c`: `uname`, `__wrap_fcntl` (FIONBIO
fallback, both refused on sockets), `getauxval` (0); `pw_wine_compat_libc.c`: kernel pipes on
Orbis (`__wrap_pipe`, `pipe2`; `WINE_ORBIS_KERNEL_PIPE=0` restores socket pairs); patches
1050/1060/1070 (diagnostic, below); the two host tests `test_wine_lookup_misses.py` /
`test_wine_root_directory.py` re-anchored on the widened gate (they failed since the widening),
and `tests/test_test_reachability.py` made to parse test rules whose flags hold `$(comma)`
(the two Orbis C test rules; it failed since abee8ea, unnoticed: a background `make test`
reports the trailing echo's exit code, so read the "make test exit N" line in the output).

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
- **Patch 1050**: Orbis stderr lines on both sides of the in-process handshake (event loop
  chosen and its first six wake-ups with the descriptors reported, client socket sent and
  received on the channel, process and first thread created, request pipe, first fds sent;
  client: socket, `fchdir` result, wait for and receipt of the request fd) and the
  `WINE_ORBIS_POLL` knob in the kqueue `init_epoll`. Drop the lines once `server connected`
  prints; keep the knob only if both loops turn out to be needed.
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
`WINEDEBUG=err+all,+loaddll,+process`; `WINE_ORBIS_POLL=1` = server main loop on `poll()`
instead of kqueue, patch 1050); `/data/ps4-wine/dev.conf` (`DEV_SERVER=`, `DEV_PORT=`
for the netlog target; the build-time default is this host's address on the route).
Fork tests: `PATH=/usr/lib/llvm-18/bin:$PATH make test` in the fork; repo: `build.sh probe-test`.
Symbolize: `llvm-symbolizer-18 --obj=third_party/prospero-win/.deps/wine-orbis/prx/<mod>.shared.elf 0x<offset>`;
the title's fault report prints `module+offset` per frame.

## Next hypotheses, in order

1. **Runs 11–14 done (LOG.md):** handshake, first requests, `server connected`, PE loader
   reached. **Run 15:** prefix with its system32/syswow64 files, kernel pipes default. Expect
   `Loaded ... kernel32.dll ... builtin`, then kernelbase, the PE side's `process_init`, and
   `hello.exe` writing "Hello from PE64" to stdout (title's STDOUT records) and exiting 0:
   the check line `server=inprocess exit=0`. Likely next walls: the PE-side `NtCreateUserProcess`
   refusal is fine (ERR only); `sigaltstack` is -1 (no alt stack: a fault handler on a full
   stack dies); `dup` refused (handle duplication, `dup_fd_object`); the only O_NONBLOCK
   refusals left are on AF_UNIX sockets (the accepted client socket: blocking `recvmsg` on
   POLLIN only, fine; `server/sock.c` for Winsock later: `MSG_DONTWAIT` per call).
   Before direct requests (`WINE_PS5_SERVER_DIRECT=1`): the wake pipe is a kernel pipe now,
   so its O_NONBLOCK works; re-check the line `O_NONBLOCK on the wake pipe ... refused` is gone.
   Reading guide for the request traces (patch 1060): read `fd message on process 0020 -> 8: client fd N for
   thread 0000, received as M` (M = -1 means the SCM_RIGHTS fd was dropped on an 8-byte
   message), `init_thread 0021: reply fd / wait fd` or its failure line, `request 0 for thread
   ... -> status, reply fd set|NONE`, `reply of 64 bytes written`, `thread killed`; client
   `wine-orbis: request 0: 64 bytes on fd 32, reply on fd N` then `request 0 -> status`.
   A thread killed without a reply fd leaves the client reading its own reply pipe forever
   (it holds the write end until after the request): once the cause is fixed, consider
   closing `reply_pipe[1]` before the request on Orbis so a server-side failure surfaces as
   EOF instead of a hang.
   (Earlier plan, done:) kqueue path + patch 1050
   traces. Read the `wineserver: orbis:` lines: `event loop kqueue (fd N)`, `kqueue loop, 2
   poll users`, then `kevent -> 1` with the master socket's ident when the client sends, then
   `client socket N received`, `process XXXX created`, `fd N sent`; on the client
   `wine-orbis: waiting for the request fd` then `request fd N, protocol 8xx` and the
   `server connected` mark. The first missing line names the step.
2. If kqueue never reports the socket: `WINE_ORBIS_POLL=1` in `env.txt`, launch again, same
   reading with `poll -> N` lines. If `poll` reports it and kqueue does not, keep the knob
   as the default on Orbis (and look at the `kevent` layout: FreeBSD 9's 32-byte struct in
   `wine/orbis/include/sys/event.h`, untested).
3. If neither loop wakes although the client's `sendmsg` returned 1: the 1-byte message is
   queued but the kernel reports nothing on the receiving end of an AF_UNIX pair from
   another thread. Then switch the channel to a `pipe()` plus an fd table, or hand the fd
   over in memory (same process: the server can `fcntl(F_GETFL)` the client's own fd number;
   `dup` is refused but the number itself is valid in both threads).
4. If the loop wakes and `receive_inprocess_client` fails: `recvmsg` errno and `controllen`
   are printed; compare with the title's probe (`CMSG_SPACE(int)` = 24, 12-byte header).
5. If the server thread never prints `kqueue loop`/`poll loop`: it blocked before
   `main_loop` (the `pthread_mutex_lock` on `inprocess_server_mutex` at its top, or
   `pthread_create` ran it on a bad stack); add a line at the start of
   `inprocess_server_thread`.
6. Once `server connected` prints: expect `dup`-dependent paths (`dup_fd_object` on
   sockets/pipes, nls mapping already covered by the reopen-by-path wrap), the PE load
   (`mmap` private file views → `pread` fallback), then signals (`sigaltstack` returned -1
   in a). `WINE_PS5_SERVER_DIRECT=1` only after the stock path connects.

## Uncommitted work

Repo (`main`, after c0dd8d2): `CLAUDE.md` (libc ENOSYS-stub trap), `docs/ps4/{HANDOFF-c,LOG,MILESTONES}.md`,
`scripts/ps4/prefix.sh` (keeps system32/syswow64 files, puts the registry files explicitly),
`tests/fixtures/c-pass.log` (the real run-15 lines), the fork gitlink.
Fork (`orbis`, after abee8ea): the runs 11–15 list under "Fork additions". Build outputs under
`.deps/` and `build/` are ignored. The console holds the runtime PRXs of the run-15 build and
the run-15 prefix; `/data/ps4-wine/env.txt` is empty.

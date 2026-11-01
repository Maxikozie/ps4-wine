# Hand-off: milestone f (32-bit EXE via the translator, then the native probe)

Written 2026-11-01, after milestone e passed and was committed (repo `ccb028a`, fork `0ec0103`).
Read `CLAUDE.md`, then this, then `MILESTONES.md` (the f row and its note), `ARCHITECTURE.md` §3.1,
§4.4 and §4.5, `HANDOFF-e.md` (how e was reached; the PRX-to-PRX recipe is in its "What d taught"
section) and the last lines of `LOG.md`.

## Resume here (2026-11-01 16:10: f1 and f2 passed)

**f1 and f2 passed on the console** (LOG.md 15:59 and 16:06, two launches of the same package,
`ps4-wine-0ec0103+dirty-f1.pkg`):
```
PS4WINE f1 hello32 cpu=translator wow_bound=19/19 fp=ok thread=ok seh=ok faults_unresolved=0 faults_guest=3 ... exit=0
PS4WINE f2 gdi32 win32u=ok pixel=ff8000 window=ok screen=800x600 ... fb=ok        -> PASS (HDMI + framebuffer)
```
- 32-bit code runs on the PS4 through `wowprospero` (the IA-32 translator), chosen by the prefix's
  `Wow64\x86` key alone. `wowprospero.prx` binds all 19 of its ntdll slots, both fault hooks
  included. Jaguar has no BMI2, so the non-BMI2 encodings ran; they had never run on the console.
- Checked in `wow32.exe`, which Wine runs on the translator:
  - x87 and SSE2 results equal the host CPU's (fsin within one ulp);
  - a second thread with its TLS slot runs;
  - SEH works: a NULL read caught by a frame handler on the fs:[0] chain, a NULL write caught
    by a VEH, and a NULL read on a second thread are each resumed after the access;
  - 3 guest faults went through patch 0610's hook, with 0 unresolved and 0 DBT errors.
- The 32-bit GDI picture (gdi64.exe built for i686) reaches VideoOut through wow64win. It is
  on HDMI for 2.0 s, recorded by the viewer itself (`view.sh --record`).
- **Below 4 GiB before Wine starts, only the eboot is mapped** (0x400000-0x650000), leaving a
  4089 MiB hole. wow32.exe (base 0x400000, relocatable) was moved to ~0x110000.
  - PINBALL.EXE has no relocations and must load at 0x01000000-0x0104b000; that range is free.
  - An EXE without relocations at base 0x400000 (many MSVC games) collides with the eboot. That
    is a risk for g/h: a different eboot base, or a check of each game's base.
- Wine's direct memory below 4 GiB is 14 MiB (peak 18). Neither RADV nor libvulkan.prx loaded.

**Next:** the user commits, fork and repo (see "Uncommitted"). Then plan `f` itself:
1. **Pad to keys** (gap 7). scePad's bits match the fork's table (`src/pw_game_profile.c`;
   OpenOrbis has no "create" bit). It needs a key mode in the play loop
   (`PW_WINE_INPUT_KEY`) with Pinball's bindings.
2. **Audio** (gap 8). On the host, Pinball starts and plays with no audio driver at all. On the
   console 0120 defaults the driver to `ps5`, and that driver is not built for Orbis.
   - **Unmeasured:** whether Pinball starts the same way on the console.
   - Porting `wine/wineps5` to `sceAudioOut` is optional for the f rule.
3. **Pinball's files** go to the prefix as `C:\Pinball\` (from `Pinball/` in the repo root, gitignored).
   - Its window opens at about 210,128 of the 800x600 desktop and runs past the right edge.
     Consider `WINE_PS5_DESKTOP=1024x768` or a larger size for plan `f`.
4. **Plan `f` and its line** (`PS4WINE f pinball cpu=translator frames>=600 faults_unresolved=0`,
   frames/s recorded). The rule stays as MILESTONES has it.
5. **f4** (native caps) after Pinball passes, as its own Orbis variant of 0883.

**Host evidence for Pinball** (not console): `tools/test_wine_ps5_driver.sh` under
`.deps/wine-host-drv` with the CPU key ran PINBALL.EXE on the translator for 40 s.
- BMI2 encodings: 2517 frames (~63 fps on the i7-13700H), the table in attract mode.
- `-DPW_X86_NO_BMI2`, Jaguar's encodings: 2465 frames, the same picture.

**Measured translator gaps without BMI2** (host, `make test-nobmi2`; asserted in
`tests/test_pw_x86_reencode.c`, so they flip when fixed). Two forms reach no path; the guest is
refused the instruction:
- `cmpxchg m8, ah/bh/ch/dh`;
- a high byte loaded through fs.

Real code rarely uses either. Pinball did not hit them on the host.

**Departures from the plan below (2026-11-01):**
- **One program per console launch.** Wine has no process creation, so `C:\wow32.exe`
  (`tests/wine_wow32.c`) runs `wine_hello32.c`'s checks, then `wine_gdi64.c`'s picture. hello32.exe
  and gdi32.exe exist as host programs too.
- **The rules:**
  - f1 is `hello32 cpu=translator wow_bound=N/N fp seh thread faults_unresolved=0 exit=0`;
  - f2 is `gdi32 win32u=ok pixel=ff8000 window=ok` plus d2's pixels. It does not read the exit code,
    which is f1's.
- **`faults_*` are wowprospero's own counters** (`wine/wowprospero/wow_stats.h`, exported as
  `pw_wow_stats`, read through ntdll's dlsym), not an ntdll counter. Only the backend knows whether
  RIP was in translated code.
  - `faults_unresolved`: the 0710 hook declined a fault inside translated code, or SIGILL there.
  - `faults_host`: Wine's own unresolved faults outside translated code (informational).
- **The checks `test_wowprospero_orbis.py` was to make are build-time checks instead:**
  - `C_ASSERT`s in `unix.c` give the frame offsets;
  - `build_wine_orbis.sh` fails when `unix.o` keeps a native `__thread`.

**Built and changed (uncommitted; the user commits):**
- **Fork:**
  - `wine/wowprospero/unix.c`: `PW_WOW_CONSOLE` covers `__ORBIS__`; trigger files go under
    `/data/ps4-wine/`; it gains the counters, `pw_wow_stats` and the Orbis `C_ASSERT`s.
  - new `wine/wowprospero/wow_stats.h`.
  - `tools/build_wine_orbis.sh`: the `wowprospero` module, and emutls always compiled.
  - `tools/build_wowprospero.sh`: `--cflags`.
  - new `tools/refresh_wine_host_drv.sh`.
  - `src/pw_x86_reencode.c`: `-DPW_X86_NO_BMI2`.
  - Makefile: `test-nobmi2` and `test_wine_wow32.py`.
  - tests:
    - new `wine_hello32.c`, `wine_wow32.c`, `test_wine_wow32.py`, `pw_test_bmi2.h`;
    - `test_pw_x86_reencode.c` and `test_pw_x86_fault_markers.c` follow the host's BMI2;
    - `wine_gdi64.c` labels its line GDI32/GDI64.
  - `native/orbis/pw_milestone_orbis.{c,h}`: plan `f1` (stages `wow_bind`, `low_map`, `display`,
    `wow32`) with its lines.
  - `wine64_main_orbis.c`: `dmem_low` in the alive record.
- **Repo:**
  - scripts: `scripts/ps4/{build,check,prefix,runtime,view}.sh`:
    - build.sh: wowprospero into the host tree, check_f;
    - check.sh: f1/f2;
    - prefix.sh: the CPU key, wowprospero.dll, hello32/wow32;
    - runtime.sh: wowprospero.dll;
    - view.sh: `--record`, `--record-max`, `--stop-record`, one queued frame in mailbox mode.
  - tests: new `tests/check_f_test.sh` and `tests/fixtures/f1-*.log`, `f2-nowindow.log`.
  - docs: `CLAUDE.md` (the viewer, CE-33237-8, recording), LOG.md, this file.

**Host test state (2026-11-01):**
- fork `make test`: exit 0, including `test-nobmi2` and `test_wine_wow32.py`;
- `build.sh probe-test`: exit 0 (a-f);
- `test_wine_vk64.py` and `test_wine_d3d11tri64.py` pass with their env set.

**Open items:**
- `runtime.sh`'s full upload compares sizes only (`mirror --only-newer --ignore-time`): a rebuilt
  DLL of unchanged size stays stale on the console.
- **Untested on the console:**
  - the 0710 unresolved hook (no fault reached it);
  - SMC write protection (`faults_smc=0`);
  - the fault rate;
  - a long run.
- The console title idles after its line. Close it before a reinstall: installing over it gave
  CE-33237-8 (CLAUDE.md).

## Milestone f

From `MILESTONES.md`:

| Deliverables | Rule (`check.sh f`) | Main risk |
|---|---|---|
| `wowprospero.dll/.prx`, the prefix selects it; Space Cadet Pinball plays; a `wow64native` readiness probe reports caps | `PS4WINE f pinball cpu=translator frames>=600 faults_unresolved=0 native_caps=<0..7>`. PASS needs only the translator fields; `native_caps=7` is recorded as a bonus | Executable memory above 4 GiB, the SEGV hook, compat-mode selectors |

prospero-win's own Pinball run (PS5 FW 12.02, `docs/CASE_STUDY_PINBALL.md` in the fork):
- the unchanged PE32 exe ran through the translator with Wine's i386 modules;
- it draws with GDI only (`BitBlt`, `StretchDIBits`) and plays sound through WinMM/WaveMix PCM;
- it was played with pad buttons bound to keys: L1/R1 = Z and `/` (flippers), cross = space
  (plunger), d-pad = X, `.` and up (nudge), options = F3 (pause), square = F2 (new game).

There is no Direct3D in f. Milestone d already covers its GDI path in 64-bit.

## Inputs (the user's)

- **Space Cadet Pinball**, owner-supplied: the files of `Program Files\Windows NT\Pinball` from a
  32-bit Windows XP install (`PINBALL.EXE`, `PINBALL.DAT`, the `.WAV` files, `PINBALL.MID`,
  `FONT.DAT`, `WAVEMIX.INF`, ...). Not in the repo (`*.exe` is gitignored). Proposed host location:
  `build/games/pinball/` (gitignored). Ask the user before choosing another one. On the console
  the files go to the prefix, `C:\Pinball\` on `/data`, uploaded once.
- Our own test programs (`hello32.exe`, `gdi32.exe`), built with `i686-w64-mingw32` like the
  64-bit ones. They are not game files.

## What carries over (read in the fork; measured where a run is named)

**The translator** (`src/pw_x86_*.c`, `pw_x87.c`, `pw_guest_*.c`, `pw_vm*.c`) is plain C with
host tests in the fork's `make test`: `test_pw_x86_*` (engine, chaining, SMC, fault markers,
lazy flags, ...), plus the `dbt_differential` and `classify_x86` tools.
- It checks for BMI2 at run time (`pw_x86_reencode.c` `host_bmi2()`, CPUID leaf 7). Jaguar has
  none, so it takes the non-BMI2 encodings. Those encodings have not run on the console.
- The guest's CPUID is the host's with AVX, AVX2, FMA and F16C removed (`pw_x86_cpuid_mask`).
  On Jaguar, the 32-bit guest sees Jaguar's features.

**`wowprospero`** (`wine/wowprospero/`): the PE side is `cpu.c` with the `BTCpu*` contract; the
Unix side is `unix.c` plus the translator.
- Its executable memory comes through Wine's VM: `place_above_guest()` →
  `NtAllocateVirtualMemoryEx`, which is direct memory under patch 0600 (already in the Orbis
  ntdll). Nothing maps `PROT_EXEC` directly.
- `unix.c` has one `__thread` (`self`). Orbis has no native TLS, but `wine/orbis/pw_emutls_orbis.c`
  (from e1) provides `__emutls_get_address`, as it does for `libvulkan.prx`.
- The PS5 build of `wowprospero.prx` is in `tools/build_wine_ps5.sh` (around lines 480–496):
  1. compile `unix.c` and the ten translator units;
  2. link with `emutls.o` and a descriptor exporting `__wine_unix_call_funcs`;
  3. ntdll is its import source.
- The host build (`tools/build_wowprospero.sh`) makes `wowprospero.dll` (x86_64-windows) and
  `wowprospero.so` inside the host Wine tree.

**Wine patches:**

| Patch | What | Orbis gate |
|---|---|---|
| 0601 | keep i386 images below 4 GiB | widened |
| 0610 | SEGV hook for the WoW64 CPU | widened |
| 0710 | guest access violations from the WoW64 CPU | widened |
| 0611 | `WINE_PS5_WOW64_CPU` names the backend | PE-side wow64, ungated |
| 0614 | fall back to the translator when the native CPU does not start | PE-side wow64, ungated |
| 0883 | native WoW64 signal entry | **PS5-only**: `tools/widen_console_gates.py` excludes it |
| 0903 | keep the FS base of a resumed 64-bit thread | **PS5-only**: excluded too |

- `ntdll.prx` already exports `__wine_ps5_set_segv_hook` and `__wine_ps5_set_segv_unresolved_hook`
  (`build_wine_orbis.sh`, ntdll's `desc` list).

**Prefix and runtime:**
- `prefix.sh` makes the prefix with `WINEARCH=wow64`, so `syswow64` exists.
- `runtime.sh` already stages `lib/wine/i386-windows`.
- The CPU is chosen by `HKLM\Software\Microsoft\Wow64\x86` (default value). `tools/pw_prefix.py`
  rewrites it in `system.reg`; `tools/run_wine_dbt_host.sh` sets it with `reg add`.

**Measured on this PS4 (milestone a, LOG.md 2026-10-30):**
- The signal frame matches the PS5's, through both `sigaction` and
  `sceKernelInstallExceptionHandler`: `frame_mc=64`, `frame_fx=320`, `frame_fs=1152`, and the RIP
  at +224 (mcontext +160).
- `sysarch` gets and sets both FS and GS (`sysarch=fs+gs`).
- A guarded far jump to selector `0x33` ran 32-bit code from an RWX page below 4 GiB and came
  back through `0x43` (`cs32=ok`).
- libkernel's `getppid` stub reads `48 c7 c0 27 00 00 00 49 89 ca 0f 05 72 01 c3`
  (`mov $0x27,%rax; mov %rcx,%r10; syscall; jb +1; ret`). The `syscall` instruction sits at
  `getppid+10`, the same shape that 0883 relies on for the PS5.
- `sigaltstack` returns -1 (c, d).

## Gaps (the work, host-testable first)

1. **`build_wine_orbis.sh`: a `wowprospero` module.**
   - Use `link_prx wowprospero - "<objects> pw_emutls_orbis.o <descriptor>" ntdll`, with ntdll as
     its one exporter; that gives the stub, the bind table and `wowprospero.bind.txt`.
   - Compile `unix.c` with `-femulated-tls`; the translator units do not need it.
   - Check what `unix.c` imports from ntdll's Unix side (`NtAllocateVirtualMemoryEx`,
     `NtQueryVirtualMemory`, `__wine_ps5_mprotect`, the hooks, ...): each must be an ntdll export.
     `orbis_import_stub.py` refuses names that libkernel also exports.
2. **`wine/wowprospero/unix.c`: 15 `#ifdef __PROSPERO__` sites.** This is fork source (LGPL), so
   it can be changed directly; a console macro covering both (`__PROSPERO__ || __ORBIS__`) is
   enough.
   - Needed for the translator to resume faults:
     - l.796, `redirect_unresolved`;
     - l.1161/1169, `__wine_ps5_mprotect` for the SMC pages (direct memory needs
       `sceKernelMprotect`);
     - l.1221, installing the two hooks. Without it, the non-PS5 path chains its own `sigaction`
       over Wine's handler (l.119), which is untested on Orbis.
   - Context access (l.694/708): Orbis builds with `__FreeBSD__` and `wine/orbis/include`'s
     mcontext. A host test should assert that RSP and RIP land at +248 and +224, the offsets
     measured in a.
   - Trigger files (`/data/prospero-win/pw_wow_*`, l.544–608, 928, 1194, 1251): point them at
     `/data/ps4-wine/`.
   - Profile output (l.848, 1003, 1080: `dladdr`, `fopen` per thread): take the console branch.
     There is no `dladdr` from a PRX.
3. **`wowprospero.dll`** (PE, x86_64-windows): build it in the host tree, and have `runtime.sh`
   and `prefix.sh` put it where Wine's PE loader finds it. Wine's PE loader maps a builtin only
   when its file is in the prefix (`prefix.sh`'s comment), so `wowprospero.dll` goes into
   `system32`.
4. **The prefix's CPU key:**
   - `prefix.sh` sets `Wow64\x86 = wowprospero.dll`. Run `pw_prefix.py`, or `reg add` with the
     host Wine as `run_wine_dbt_host.sh` does.
   - The title can also set `WINE_PS5_WOW64_CPU=wowprospero.dll` (0611).
   - Then `test_pw_wine_prefix_cpu` covers it.
5. **Test programs** (`prefix.sh --extras`):
   - `hello32.exe`, from a new `tests/wine_hello32.c` in the fork. It prints, then deliberately
     reads NULL inside `__try`/`__except`, so an SEH catch exercises 0610, 0710 and the hooks. It
     also does one x87 and one SSE2 computation with known results, and runs a second thread.
     Exit 0 only if all of these pass.
   - `gdi32.exe`, the fork's `tests/wine_gdi64.c` built for i686. It draws d2's picture through
     `wow64win`.
6. **The title:**
   - New plans `f1` (`hello32.exe` + `wowprospero.prx`'s slot check, like e's `wv_bind`), `f2`
     (`gdi32.exe`) and `f` (Pinball) in `pw_milestone_orbis.{c,h}`.
   - `faults_unresolved` is not counted anywhere yet. Count the faults that neither Wine nor
     `redirect_fault` resolved: a counter in ntdll's 0710 path, read like
     `__wine_ps5_memory_stats`.
7. **Pad to keys for Pinball.**
   - d's pad loop posts only pointer and click events. The key event type exists
     (`PW_WINE_INPUT_KEY` in `pw_wine_sink.h`).
   - The bindings (`PwGameBinding`: pad button mask → Windows virtual key) and the preset parser
     are in the portable `src/pw_game_profile.c`.
   - scePad's button bits are assumed to match the DualSense's. Check this against OpenOrbis's
     `pad.h` before binding.
8. **Audio:** Orbis has no audio driver yet (`build_wine_orbis.sh`'s module list has no
   `wineps5`/`wineorbis`). Before the console run, check on the host what Pinball does with no
   audio device (Wine's audio driver set to none). If it refuses to start, porting
   `wine/wineps5/unix.c` to `sceAudioOut` (ARCHITECTURE §4.11) becomes part of f.

**Native readiness (the bonus, last):**
- `native_caps` needs 0883 for Orbis:
  - a raw `sigaction` (syscall 416) through the `syscall` at `getppid+10` (the shape is measured);
  - the frame check with a marked MXCSR (frame offsets measured);
  - an aligned alternate signal stack, which is a problem: `sigaltstack` returns -1 through libc
    here. Whether syscall 53 through the same stub works is **unmeasured**.
- Keep 0883's rule: caps 0 unless every check passes, and the translator runs either way.
- Do not widen 0883 and 0903 wholesale: write the Orbis variant as its own patch, after Pinball
  passes on the translator.

## Sub-steps (proposed; fix each rule in `check.sh` and a `tests/check_f*_test.sh` before its first run)

| Step | What | Proposed rule |
|---|---|---|
| f1 | `wowprospero.prx` loaded and bound; `hello32.exe` through the translator: SEH catch of a guest fault, x87/SSE2, a second thread | `PS4WINE f1 hello32 cpu=translator wow_bound=N/N seh=ok fp=ok thread=ok faults_unresolved=0 exit=0` |
| f2 | `gdi32.exe` (32-bit GDI through `wow64win` to the present sink); same launch as f1 | d2's pixels: 960,540 = 0,255,0 and 780,410 = 255,128,0, on `--fb` **and** over HDMI (see below) |
| f | Space Cadet Pinball, played by the user with the pad bindings above | the f rule; an HDMI frame of the table as evidence (no pixel gate in the rule) |
| f4 | the native readiness probe (bonus) | `native_caps` recorded in the f line, not gated |

## Host first

- Fork: `PATH=/usr/lib/llvm-18/bin:$PATH make test`. It has not been run in full since e2, and the
  translator's tests are part of it.
- `tools/run_wine_dbt_host.sh --cpu dbt` with `hello32.exe`, `gdi32.exe` and Pinball under the
  host Wine with `wowprospero.so`, then `--cpu native` as the control. A Pinball run without an
  audio driver goes here too (gap 8).
- `build.sh probe-test`, and `tests/check_f*_test.sh` with fixtures, as for e.
- The Orbis link report (`orbis_prx_report.py`) for `wowprospero.prx`: no unresolved imports, no
  raw syscalls.

## Risks (unmeasured on the PS4)

- **The address space below 4 GiB.** Wine's i386 side needs the low 2 GiB (0601, 0895).
  - Where the eboot, libkernel's helpers and flexible-memory placements sit below 4 GiB on Orbis
    has not been mapped.
  - a found one free 16 KiB page between `0x10000000` and `0xFF000000`; that is not a 2 GiB hole.
  - Have the f1 title log Wine's low reservation result (`PW_WINE64 memory`, `dmem_low`).
- **The fault rate.** SMC protection and guest faults go through the SEGV hook. nx-on-orbis
  measured ~4.9 µs per fault through `sceKernelInstallExceptionHandler`; the `sigaction` cost has
  not been measured here.
- **Speed.** The translator runs at 85–93 % of native on Zen 2. 6 Jaguar cores at 1.59 GHz will be
  slower. Pinball is light, so record frames/s in the f line.
- **Thread budgets** (`thread_budget.h`: per-thread arena sizes) against ~4.4 GiB of direct memory
  with RADV's 1 GiB arena idle. f has no Vulkan; check that RADV is not loaded in plan f.
- **`pw_vm_posix.c`** maps with `PROT_EXEC` when asked to. wowprospero gives the translator Wine's
  VM instead, but a host test should show that no `PROT_EXEC` mmap reaches libc on Orbis.

## HDMI (new since e)

- The stick is described in `CLAUDE.md`'s Screen row.
- For f2's short-lived picture, record the launch (`ffmpeg ... -c copy logs/<ts>-f-hdmi.mkv`; a
  `-f tee` into `ffplay` keeps the user's view), stop it with SIGINT after the line, then take a
  frame with `ffmpeg -ss T`.
  - T = the log's present time minus the recording's start time.
  - e's recording read 7,7,7 outside the Vulkan swapchain's lifetime.
- For Pinball, `shot.sh` works while it plays, after `view.sh` is closed.
- Each LOG line says which check passed: HDMI, framebuffer or both.

## Open items carried from e

- 0480 is in the runtime through a hand-built `opengl32.dll`. The next `build.sh wine`
  reconfigures and rebuilds both trees with it. Refresh `.deps/wine-host-drv/build` afterwards, as
  `HANDOFF-e.md` (e2+e3) describes.
- `build.sh probe-test` has not been rerun since e4's changes.
- `tests/test_vk_radv_profile.py` fails once a Vulkan header is found (`clock_gettime` under
  `-std=c11` in `wine/ps5/pw_vulkan_radv.c`). Latent, not f's.
- `err:environ:run_wineboot failed to start wineboot c00000bb` in 18 logs from c on. Not new,
  not followed up.

## Iteration loop (as in e)

```
scripts/ps4/build.sh wine --skip-host        # Orbis PRXs (+ wowprospero.prx once gap 1 is in)
scripts/ps4/runtime.sh --prx-only            # PRXs + *.bind.txt to /data (sizes verified)
scripts/ps4/runtime.sh                       # once: wowprospero.dll and the i386 PE modules
scripts/ps4/prefix.sh --extras               # hello32.exe, gdi32.exe, the CPU key
scripts/ps4/build.sh title                   # when native/orbis changed
cp dist/ps4-wine-<id>.pkg dist/ps4-wine-<id>-<tag>.pkg && scripts/ps4/deploy.sh dist/ps4-wine-<id>-<tag>.pkg
scripts/ps4/logs.sh --label fN --expect 'PS4WINE fN ' --timeout 7200 &   # before the user launches
scripts/ps4/check.sh fN --fb                 # plus the HDMI check where there is a picture
```

Choose the plan with `PS4WINE_MILESTONE=<plan>` in `/data/ps4-wine/env.txt`. Give each package
build its own file name, so an install never reads a file that is still uploading (d5's broken
install).

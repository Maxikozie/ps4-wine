# Hand-off: milestones i-n (Psychonauts)

Written 2026-11-02, after Bloodlines was parked at g (`HANDOFF-g.md`, "Parked 2026-11-02"). Read `CLAUDE.md`, then
this, then `MILESTONES.md` (rows i-n), `ORBIS-WIN.md` (row 16, F14) and `HANDOFF-g.md` (plan g's machinery, which k-n
reuse). Everything here is desk work: nothing was built or run on the console for i-n. The letters A-D refer to the
research sections at the end; F = `third_party/prospero-win`, R = the repo root.

**Playable** means: from the PS4 menu into gameplay with the DS4, with sound, a save and a load, a 30-minute session,
at the frame rate fixed below (`fps_avg>=30`, `fps_avg<=61`).

## Resume here

**State at the end of planning (2026-11-02):**
- Bloodlines is parked at g (`HANDOFF-g.md`, "Parked 2026-11-02"). Nothing for i-n is built. Every rule below was fixed
  on 2026-11-02, before its first run. Each `check.sh` rule and its fixtures are written before that step's first
  launch.
- **Psychonauts is extracted.**
  - The installer was moved to `games/game-psychonauts/`, then `innoextract --gog -d games/psychonauts` ran (exit 0).
  - `games/psychonauts/` holds `game/`, `support/app/`, `__unpacker/`, Inno's `app/`, and `tmp/` (the installer's 110 UI
    files, 34 MB).
  - Checked against `lsar -j` of both volumes: all 1774 files and 5,510,306,912 B are present, with every size equal.
  - The file that spans both volumes, `game/WorkResource/Sounds/commonfx.isb` (13,439,438 B), has CRC32 0x13ef04e9,
    which is the whole-file CRC in volume 2's header.
  - `pe_bases.py games/psychonauts` reproduces A's table (plus `tmp/`'s installer DLLs).
  - `games/` is read only from here on.
- **The console:**
  - title `ps4-wine-c76b600+dirty.pkg`;
  - `env.txt` = `PS4WINE_MILESTONE=g`, `PS4WINE_AUDIO=on`, `WINEDEBUG=+loaddll` (L15);
  - Bloodlines at `C:\VTMB` (4,310,145,998 B), and `/data/ps4-wine` at 5,096,744,725 B in total.
  - Psychonauts is not uploaded.
  - Free space on `/data` is unknown: FTP and statfs cannot tell, so the user reads Settings → Storage before k.

**j passed (host), 2026-11-03.**
- The rule passed on session A (2026-11-02).
- Wine bug 20834 broke the restart check (stop point S3). Fork Wine patch 0904 fixed it.
- The restart proof passed in sessions C, D and E: the pad's buttons work after restarts, and the bindings INI is
  unchanged.
- Details: "j result" and "The S3 fix" under j below.
- Built:
  - `host-game.sh --game psychonauts`;
  - the fork's evdev pad shim (`tests/host_pad_evdev.c`);
  - patch 0904 and its host test (`tests/test_wine_mapvk.py`);
  - `check.sh j` and `tests/check_psy_test.sh`.
- Not run: j2.
- Saves are in `C:\Psychonauts\Profiles\Profile 1\`, copied to `build/saves/psychonauts/`.

**i1 built, not run (2026-11-03):**
- `build.sh lowbase` → `dist/lowbase-d6e290c+dirty.pkg`: title `PSWN00003` ("ps4-wine lowbase"), the stub eboot
  (`probes/lowbase/stub.c`) plus `sce_module/lowbase.prx`, `lowbase_mod.prx` and `lowbase_mod2.prx` (`pkg.sh --prx`).
- Build gates passed: no raw syscall; the exports are present; every PRX PT_LOAD is 16 KiB aligned; the stub NEEDs
  every Sce library of `lowbase.prx` and `lowbase_mod.prx` (`mod2` alone NEEDs `libSceRtc`); the stub's PT_TLS is
  24 B `.tbss` (filesz 0, align 16) ≥ `lowbase.prx`'s 16 B (`lb_tls` at TP-16, musl's locale at TP-8, local-exec).
- The release is the fork's `src/pw_eboot_release.c`: page-rounded, merged ranges (today's eboot: one range,
  0x400000-0x6cc000); `test_pw_eboot_release` and the whole fork `make test` pass.
- `check.sh i1` (the rule above, verbatim), `tests/check_i_test.sh` (7 fixtures: pass, Home-death after the line
  still PASS, release refused, reserve refused, alive 590, a recorded field's fault, stage records only) and the
  i1 line formatter test pass in `build.sh probe-test`.

**i1 passed (2026-11-03 01:42, LOG L16, `logs/20261103-012652-i1.log`): row 16 carries to the Slim.** S1 does not
apply. Measured, and what each result decides for i:
- The stub's 3 segments (0x400000-0x508000) were unmapped as one range. Module 0's info still lists them afterwards
  (`module0_after=listed:3`), and nothing read them: 4 unwind frames, none in the range.
- After the release, all of these worked: the reserve at 0x400000 (it was refused before the release, 0x8002000c),
  direct memory mapped there with RX code, a second VideoOut open (HDMI blue), the keyboard sysmodule load with
  `sceKeyboardOpen`, app PRX loads, 8 threads, the PRX's local-exec TLS in the stub's 24 B `.tbss`, C++ throw/catch,
  FreeBSD `sigaction`, and `sceGnmSubmitDone` (rc 0 on every 100 ms tick).
  - **For i:** HID's sysmodule retry may stay after the release.
  - **For i:** the stub `.tbss` rule holds as built.
- **The pad fails after the release:** `scePadOpen` 0x80920005. The probe did not log `scePadInit`'s rc; read as
  not-initialized, `scePadInit` itself failed. **For i:** `scePadInit`/`scePadOpen` move before the release, for
  every plan (g's `g_script`, d/f/p's pad opens). After the release, only reads.
- **AudioOut open 0x809b0001** is the initial-user refusal measured in a and p5, not the release. The title opens
  with the system user and before the release. Nothing to do.
- **A PRX NEEDing `libSceRtc`, which the stub lacks, loaded and ran after the release** (`prx_sce=ok`). The stub's
  "NEED every Sce library" is a safeguard, not a requirement. i keeps it anyway: it costs nothing.
- **Home and back** (focus to NPXS20001 for 13 s) did not suspend the title: the ticks went on without a gap. The
  user's close was a normal KillApp. klog showed the known `gbase_gvmsw_close` 0x804c0005 and no exception.
- GoldHEN plugins: `[default]` `game_patch.prx` only.
- Not tested: Wine, sessions past 10 minutes after the release (the run lasted 690 s), rest mode, LoadExec.

**Next, in order:**
1. **i1 passed:** commit fork + repo (the user).
2. **i**, the title split, with **l1** in the same package. The runtime then carries 0904, and its regressions cover
   it.
3. **Still open from j:**
   - rumble not felt;
   - the touchpad's udev rule;
   - j2, only on the user's word;
   - the first-launch name screen needing Enter (planned under l).

**Corrections the research found (applied 2026-11-02):**
- `ORBIS-WIN.md` F14 and row 16 (B, "Two corrections").
- `HANDOFF-f.md:55-59`: the eboot's range is stale. It reaches 0x6cc000 now.
- Still to change in i: `pe_bases.py`'s `EBOOT` constant.
- `check.sh g` did run four times before the menu; it never ran on a gameplay window (`HANDOFF-g.md`, "Parked").

**Corrections (2026-11-03, planning i1; read against the fork at `f3e37cc`):**
- Line drift in B: `early_fault` is `wine64_main_orbis.c:286-325` (`:327-338` is `install_early_fault_report`);
  `build_native_orbis.sh` flags `:72-75`, sources `:76-81`, link `:93-98`; `stage_fault` `pw_milestone_orbis.c:3230-3250`
  (`:3252-3266` is `set_handlers`, `set_handlers(NULL)` at `:3364`); the stage exit hook is set at `:1969`.
- "Built `-femulated-tls` like the other PRXs" (i2) is wrong. ntdll, win32u and wineserver are built without it; only
  wowprospero's `unix.c`, wow64native and RADV use it. The title has no `__thread`; its only TLS is musl's
  `__musl_current_locale` (8 B `.tbss`). lld relaxes a PRX's TLS to local-exec offsets into the main executable's block
  (`F/wine/orbis/pw_emutls_orbis.c:4-14`), so the stub's PT_TLS block holds every PRX's musl locale: the stub's PT_TLS
  must stay ≥ the largest PRX PT_TLS and `.tbss` only (filesz 0). Today's eboot: memsz 8, filesz 0. This answers B's
  open question "whether the stub needs a PT_TLS": yes (inference; i1's `tls` measures it).
- NEEDED: the Wine PRXs record Sce libraries by absolute path, so a stub/PRX comparison goes by basename.
  libvulkan.prx NEEDs `libSceGnmDriver`, which the eboot does not NEED, and it runs (e passed): orbis-win's "the stub
  must NEED every Sce library" (their 10110 lacked libSceSysmodule) holds at least for some libraries only. i1's
  `prx_sce` measures a PRX loaded after the release that NEEDs a library nobody else does.
- The release must not depend on the display stage having run: a relaunch skips passed stages
  (`F/native/orbis/pw_stage_orbis.c:67-70`) and some plans have no `stage_display` (gc1), so the release could precede
  every `sceVideoOutOpen` of that process (GLDS10044). i2 opens and closes VideoOut once before the release when nothing
  opened it (`vo_prime`).
- `pw_prx_parse_module_info` takes at most 4 segments (`PW_PRX_MAX_SEGMENTS`); today's eboot has exactly 4 PT_LOADs.
- gc2 already has a stage named `release` (`pw_milestone_orbis.c:2073`): the new names are `eboot_release` /
  `pw_eboot_release`.
- Every plan line goes through `emit_line_with()` (`pw_milestone_orbis.c:3599`); c's line is the exception
  (`wine64_main_orbis.c:122-127`, `report()`). `eboot_release=` is appended in both.
- i1 gets its own title, `PSWN00003` ("ps4-wine lowbase"), as the triangle has `PSWN00002`, so the installed Wine title
  and its data stay as they are.
- The module-info parse and the release are written once in the fork (`F/src/pw_eboot_release.{c,h}`, test
  `F/tests/test_pw_eboot_release.c`); the i1 probe compiles them from the submodule, so i1 tests the code i2 runs.

## The plan

### Order (changed from the user's proposal, with reasons)

| Order | Step | Why |
|---|---|---|
| 1 | **j** (host) first, or alongside i1 | No console. It settles most of A/D's unknowns before any upload: save path, bindings after a restart (the `MapVirtualKeyEx` bug), `steam_api` failure, OpenAL→dsound, English-only data, cutscenes, mixed 16 KiB pages (`WINE_HOST_PAGE_SIZE=16384`), and the XInput path through 0470 with the laptop's DS4 |
| 2 | **i1**, then **i** | i1 is the probe; i is the title split |
| 3 | **l1** rides in i's package | It needs `xinput1_3.prx`, a runtime change that forces g1n/g1m/g1/e anyway, and i's title split forces the same set. No regression program loads xinput (Bloodlines imports dinput8), so the two do not confound. One regression round instead of two |
| 4 | k, l, m, n | as proposed |

The game picker is a later milestone, not planned here.

### The frame rate (fixed 2026-11-02, before any Psychonauts run)

**`fps_avg>=30` and `fps_avg<=61`** over the window (m: 300 s, n: 1800 s), from RADV's present counter as in g.

- **Floor 30:**
  - It is half the 60 Hz scan-out. Under VSync (the shipped `DisplaySettings.ini` has `VSync=true`) a frame lasts a
    whole number of vblanks, so an average of 30 means most frames take two vblanks or fewer.
  - A 3D platformer's jumps, pole swings and camera need that, so the floor sits above g's 20 (an RPG).
  - It is reachable but unmeasured: the readme's minimum (PIII 1 GHz, GeForce 3) is far below one Jaguar core and 18 GCN
    CUs, and the same stack ran Bloodlines' gameplay at ~50 fps (the user's L15 observation).
- **Ceiling 61:** the game's physics break above 60 fps (D: doors, trampolines, poles).
  - The cap is Psychonauts' DXVK config, `d3d9.maxFrameRate = 60` (the option is in 2.6.2's x32 `d3d9.dll`), so it
    does not depend on the game's VSync reaching our WSI.
  - The ceiling stays in the rule as the check that the cap holds.
- Recorded, not gated: `frame_us_avg/p95/max`, `hitches_50ms`.
- The original Xbox frame rate was not found, so it is not used as a reason.

### Regressions

- Any title or runtime change: g1n, g1m, g1 and e, by their own rules, before any game launch (`HANDOFF-g.md:241`).
- Plus g2 whenever plan g's code or the eboot changes (i, k).
- A title-only change that touches no plan code may skip them only where `HANDOFF-g.md:241` allows.
- Each package carries every plan that is ready; launches differ by env.txt only.

### i: low base (row 16)

**Goal:** a PE32 fixed at 0x400000, without relocations, runs on the PS4, and Wine sessions survive the eboot's release.

**i1, the probe** (repo, `probes/lowbase/`).

*What is built:*
- `stub.c` + `lowbase_prx.c`, from orbis-win's `reloc-wine-app/stub.c` and `app_entry.c` with `From:` lines and a
  `THIRD_PARTY.md` row (LGPL-2.1+ into this GPL repo is fine).
- A `build.sh lowbase` target and `pkg.sh --prx FILE` (the PRX into `sce_module/`).

*The stages, in one launch.* Each is logged and fsync'd to a progress file, as probe a.

| # | When | Stage |
|---|---|---|
| 1 | before | `direct_mib` (`sceKernelGetDirectMemorySize`): the grant with a stub eboot |
| 2 | before | VideoOut open #1, one green flip |
| 3 | release | module 0's segments, each `sceKernelMunmap`'d. Logs `segs`, `low_end`, and whether module info still lists them afterwards |
| 4 | after | `reserve400`: `sceKernelReserveVirtualRange(0x400000, 0x40c000, FIXED\|NO_OVERWRITE)` |
| 5 | after | `exec400`: direct memory mapped RW at 0x400000-0x80c000, a code stub copied to 0x401000, `sceKernelMprotect` RX, called (the shape of Wine mapping Psychonauts at 16 KiB) |
| 6 | after | VideoOut open #2 with a blue flip (`vo2`), the HDMI evidence |
| 7 | after | first `sceSysmoduleLoadModule(keyboard)` + `sceKeyboardOpen` (`sysmod`, `kbd_open`) |
| 8 | after | `scePadOpen` + read (`pad`) |
| 9 | after | a second PRX loaded, its `module_start` called, `dlsym` (`prx`) |
| 10 | after | 8 threads created and joined (`threads`), a TLS variable in each (`tls`) |
| 11 | after | C++ throw/catch and `_Unwind_Backtrace` (`unwind`) |
| 12 | after | a SEGV caught and recovered by the PRX's sigaction handler (`fault`) |
| 13 | after | one AudioOut grain (`audio`) |
| 14 | after | a heartbeat every 10 s for 600 s (`alive_s`). The loop calls `sceGnmSubmitDone` on every tick (`submitdone` = the first nonzero rc, else 0). At 600 s the i1 line is emitted |
| 15 | after the line | the user goes PS → Home and back once. Recorded only, as a `PW_MS stage=suspend` record (`resumed`, `gap_s`), not in the i1 line: never gated, never S1. The title already dies on suspend without `sceGnmSubmitDone`, before any release (LOG L9/L10), so a death here says nothing about row 16 |

*Rule:* `check.sh i1`:
`PS4WINE i1 lowbase direct_mib>=4000 release=ok reserve400=ok exec400=ok vo2=ok prx=ok threads=ok tls=ok fault=ok alive_s>=600 faults_unresolved=0`.
- Recorded in the line: `segs`, `low_end`, `module0_after`, `sysmod`, `kbd_open`, `pad`, `unwind`, `submitdone`,
  `audio`. In the LOG note: the GoldHEN plugin list and stage 15's suspend record.

*Host tests:*
- `tests/probe_util_test.c` grows a module-info segment parser test (fixture blobs) and the release-range maths.
- `tests/check_i_test.sh` with fixtures: pass, release refused, reserve refused, stage records only.

*Not tested:* Wine, sessions past 10 minutes, rest mode, LoadExec.

**Stop point S1.** If any gated field fails, stop: row 16 does not carry to the Slim as it is. Report it and replan;
j's host work stays useful. `sysmod`, `kbd_open` and `unwind` only move code: for example, open HID before the release.
Going Home (stage 15) never triggers S1.

**i2, the title as stub + PRX** (fork, LGPL; ported pieces carry `From: plastikman/orbis-win ... @ 2610706
(LGPL-2.1-or-later)`).

*The stub, `native/orbis/pw_stub_orbis.c`:*
- It NEEDs every Sce library the PRX needs. `build_native_orbis.sh` fails the build otherwise, comparing
  `llvm-readelf -d` of both.
- It loads `/app0/sce_module/ps4wine.prx`, calls its `module_start` (our recipe), finds `pw_title_main` through the
  descriptor, calls it with argc/argv forwarded, and idles.
- The title PRX lives in `/app0`, so the title stays one package with one build id. A title change is a reinstall, as
  today.

*The title PRX:*
- Every object of today's eboot (B, "Our title today"), linked by `ld_prx`'s recipe and built `-femulated-tls` like the
  other PRXs.
- Its own orbis-compat copy and its own musl: no environ. The stub forwards argv, and env.txt is read as today.
- All sinks, hooks, `argv` and environment strings then live in the PRX, so nothing handed to ntdll dangles.

*The release:*
- `pw_eboot_release()`, from `app_entry.c`, releases every module-0 segment. The range is derived, not a constant.
- It is called in `wine64_main_orbis.c` after the stages and before `pw_wine_start_run` (`:711-714`). The stages
  include VideoOut's first open, AudioOut, and the pad/HID opens, which move out of `g_script` to before the release.
- It is always on, so every regression runs released. `PS4WINE_EBOOT_RELEASE=0` in env.txt keeps the eboot, as the A/B.
- Every plan line gains `eboot_release=ok|off|<rc> low_end=0x...`.

*Also in the package:*
- `sceGnmSubmitDone()` once per main-loop tick (row 1, title only; its rc is logged once). The PS-button kill matters
  for n's 30 minutes. Recorded, not gated.
- `scripts/ps4/pe_bases.py`: `EBOOT` set to the measured end, and the verdict for fixed 0x400000 images becomes "loads
  once the title releases the eboot (i)". `HANDOFF-f.md:55-59` gets a stale-range note.

*The test program, `tests/wine_fixed32.c` → `fixed32.exe`:*
- Built by `prefix.sh` with `i686-w64-mingw32-gcc -Wl,--image-base,0x400000,--disable-dynamicbase,--disable-reloc-section`.
- Psychonauts' shape: a 4 MiB array so SizeOfImage ≥ 0x40c000, and 4 KiB sections sharing 16 KiB pages (R/RX/RW).
- It prints `FIXED32 base= relocs= size_kib= text_rx= rdata_ro= data_rw= seh= thread=`. `rdata_ro` means a write to
  `.rdata` raises an access violation, caught by SEH.
- Plan `i` runs `C:\fixed32.exe` on the native CPU.

**Rule `check.sh i`** (fixed 2026-11-02, before its first run):
`PS4WINE i fixed32 bits=32 cpu=native eboot_release=ok base=0x00400000 relocs=0 size_kib>=4144 text_rx=ok rdata_ro=ok data_rw=ok seh=ok thread=ok faults_unresolved=0 exit=0`.
- It also requires LOG.md to hold PASS lines of the same build for g1n, g1m, g1, e and g2, each showing
  `eboot_release=ok`. `check.sh` greps them.

*Host tests:*
- Fork `make test`: the module-info parser, the release range, argv forwarding.
- `fixed32.exe` under the headless `wine-host-drv`, normal and with `WINE_HOST_PAGE_SIZE=16384`, checked by
  `tests/test_wine_fixed32.py` (as `test_wine_d3d9tri32.py`).
- `pe_bases.py` on it: fixed, base 0x400000, size ≥ 0x40c000.
- The stub/PRX NEEDED comparison.
- `tests/check_i_test.sh` fixtures:
  - pass;
  - base relocated (fails);
  - c0000018 (fails);
  - release off (fails);
  - a missing regression line (fails).

*Console launches* (one package, `ps4-wine-<id>.pkg`, which replaces the installed `c76b600+dirty`; env.txt only
changes between launches):
1. i (`fixed32.exe`)
2. g1n
3. g1m
4. g1
5. e
6. g2. The user then leaves Bloodlines on its menu for 600 s after the release. Only after that, Home and back once:
   recorded only, never S2.
7. l1 (below)

*Not tested:* Psychonauts itself, sessions past 10 minutes after the release, rest mode, LoadExec.

**Stop point S2.** Stop if any of these happens:
- a regression passes with `PS4WINE_EBOOT_RELEASE=0` but fails released;
- `fixed32.exe` is refused (c0000018) or relocated;
- the g2 run dies before its 600 s on the menu (going Home afterwards is recorded only, never S2).

Then a Wine session does not survive the release. Stop before any Psychonauts upload and report.

**Commit** fork and repo after i1 passes and after i passes (the user commits).

### l1: the DS4 as XInput controller 0, sample program (rides in i's package)

**Runtime (fork `tools/build_wine_orbis.sh`):** `xinput1_3.prx`, no Wine patch change.
- `xinput1_3` added to the module list (`:40`).
- `dlls/xinput1_3/unixlib.c` compiled with `-D__WINESRC__ -DWINE_UNIX_LIB -D_REENTRANT`.
- `desc xinput1_3 __wine_unix_call_funcs __wine_unix_call_wow64_funcs`.
- `link_prx xinput1_3 ... ntdll`.
- `runtime.sh` already copies every `*.prx`.

**Title:**
- **The feed is fully off unless the profile's `[input] mode` is `xinput`:** no slot set connected, no pad feed, no
  `set_pad`/`rumble` lookup. Bloodlines (`mode = keyboard`) therefore runs L15's input code in i's regressions. Plan l1
  loads a small profile, `profiles/xinput32.ini` (`C:\xinput32.exe`, `[input] mode = xinput`), pushed by `prefix.sh`.
- The DS4 → `PwWinePad` feed: orbis-win's `pw_pad_ps4.c` ops, ported with a `From:` line and the touch block copied.
- Connected (byte 76), intercepted → connected + neutral.
- The touchpad: left-half click = Back, right-half click = the title's mark, on release.
- In xinput mode only, slot 0 is set connected before `pw_wine_start_run`, because Psychonauts checks for a pad only at
  startup (D).
- Rumble → `scePadSetVibration`.
- `[input] mode = xinput` is read on Orbis, and `pw_wine_set_pad`/`pw_wine_rumble` are looked up in ntdll.prx.

**Sample program:** `tests/wine_xinput32.c` → `xinput32.exe` (i686; `LoadLibrary("xinput1_3.dll")`).
- 30 s in which the user presses every button once, takes both sticks to their extremes and pulls both triggers fully.
- Then 1 s of rumble on each motor.
- It prints `XINPUT ...`, and plan l1 embeds that line.

**Rule `check.sh l1`:**
`PS4WINE l1 xinput32 bits=32 get0=0 caps=0 buttons_seen=0xf3ff lx_min<=-30000 lx_max>=30000 ly_min<=-30000 ly_max>=30000 rx_min<=-30000 rx_max>=30000 ry_min<=-30000 ry_max>=30000 lt_max>=250 rt_max>=250 set0=0 rumble_events>=2 faults_unresolved=0 exit=0`.
- Recorded: `get1` (1167 expected), vid/pid, packets, `vibration_rc`, and the user's word that the motors ran.

**Host tests:**
- Fork unit tests: the converter (touch halves, the connected byte, intercepted) and rumble scaling.
- `xinput32.exe` under the host Wine with an `LD_PRELOAD` fake sink exporting `pw_wine_pad_at`, so 0470 takes the
  title-pad path.
- `tests/check_l_test.sh`.

**Not tested:** the game's own pad handling; the bindings bug.

**Stop:** if `get0` is not 0 on the console with the PRX staged, stop; read the PRX's load error before touching the
game.

### j: Psychonauts on the laptop (host; no LOG.md line, its result goes into this file)

**Changes:**
- `scripts/ps4/host-game.sh --game vtmb|psychonauts`. The default stays `vtmb`, so the user's command is unchanged.
- For psychonauts:
  - the copy `build/host-game/psychonauts` is a reflink of `games/psychonauts/game`, minus `WorkResource/Sounds/{French,German}`
    (the console's file set), plus `support/app/*.ini` in its root;
  - the prefix `build/prefix-desktop-psychonauts` (never `build/prefix-desktop`) with `C:\Psychonauts` linked;
  - DXVK x32 d3d9 with `d3d9=n`, and the console's `dxvk.conf` (`d3d9.maxFrameRate = 60`) through `DXVK_CONFIG_FILE`;
  - the working directory is the game folder, the 1920x1080 virtual desktop, `--census`, `--saves-out`.
- Fork `tests/host_pad_evdev.c`: an `LD_PRELOAD` library exporting `pw_wine_pad_at` (and the other slot and rumble
  calls). It is fed from the laptop's DS4 over evdev, with the touchpad halves mapped as on the console, so the game
  reads the pad through 0470's title-pad path, as on the PS4. `host-game.sh --pad /dev/input/eventN`.
- j2: Psychonauts to its main menu on the headless `wine-host-drv` (the console's driver code) with lavapipe and PPM
  frames, normal and `WINE_HOST_PAGE_SIZE=16384`, as HANDOFF-g's H4.

**Recorded:**
- the EXE at 0x400000 (`+loaddll`);
- the DLL census: native OPENAL32/isactwin/AudioDrv/binkw32/steam_api/ogg/vorbis, builtin d3dx9_40/msvcr90/xinput1_3/
  dsound/dinput8;
- whether `steam_api` failing is tolerated;
- the save path (inferred `<game>\WorkResource\SavedGames`) and where bindings live;
- bindings after a restart, with `+keyboard` around `MapVirtualKeyEx`;
- sound through OpenAL→dsound;
- the intro and the 2nd cutscene;
- crossings per frame;
- saves at fixed spots (`j-camp` at the summer camp), for m and n.

**Rule `check.sh j`:** `host-game.sh` prints `PS4WINE j psychonauts exe_base= dll_missing= presents= save_new= pad_reads=
session_s=` when the game exits. The rule is:
`exe_base=0x00400000 dll_missing=0 presents>=3600 save_new=1 pad_reads>=1 session_s>=600`.
- It also needs the user's word on menu, gameplay, sound, a save and a load, and the bindings after a restart.
- `tests/check_psy_test.sh` holds the fixtures for j, k, l, m and n.

**j as built (2026-11-02, before session A).** Changes from the plan above:
- **Where the copy lives.** The copy is `build/prefix-desktop-psychonauts/drive_c/Psychonauts` itself, and
  `build/host-game/psychonauts` links to it.
  - The game takes its INIs and saves from `_getcwd`. Behind a link, `getcwd` resolves to `Z:\home\...`.
  - Double Fine documents glitches when the game is not on C:.
  - Setup dies unless `wine cmd /c cd` run from the copy prints `C:\Psychonauts`.
- **winebus `Enable SDL`=0.** It changes nothing on this Wine and only documents the setting.
  - The desktop Wine has neither SDL nor udev: `.deps/wine-host-desktop/build/include/config.h` leaves
    `HAVE_SDL_H`, `SONAME_LIBSDL2`, `HAVE_UDEV` and `HAVE_LIBUDEV_H` undefined, and its `winebus.so` has no
    libSDL2 string.
  - So winebus never sees the DS4, and the preloaded shim is the pad's only route, as on the console.
  - Smoke run (17:12): the game's `EnumDevices(DI8DEVCLASS_GAMECTRL, ATTACHEDONLY)` found nothing. It created only
    the system keyboard, and the prefix has no `Enum\HID` or `Enum\WINEBUS` key.
- **The pad shim.** Fork `tests/host_pad_evdev.c` (`make host-pad`) is an x86_64 `LD_PRELOAD` that exports only
  `pw_wine_pad_at` and `pw_wine_set_rumble_at`.
  - It maps the buttons with `pw_wine_game_pad`'s table. Share and PS are dropped, as the console's DS4 never gives
    them to a title.
  - The touchpad's left half is Back while held. Its right half is the mark: `host_pad mark N` in the log, never
    passed to the game.
  - Rumble goes out as FF_RUMBLE.
  - `host_pad_monitor` checks the mapping without Wine. Every button, both sticks over their full range, and both
    triggers to 255 were seen on event26 (2026-11-02).
  - The touchpad node (`ID_INPUT_TOUCHPAD`) has no uaccess ACL. Until the user adds a udev rule for it, there is no
    Back and no mark.
- **Field definitions of the j line**, fixed before session A:
  - `exe_base`: the `+loaddll` base of `Psychonauts.exe`.
  - `dll_missing`: the distinct DLLs the game lacks. That is the imports Wine could not satisfy for a module under
    `C:\Psychonauts`, plus every DLL `Psychonauts.exe` imports or loads by name (OpenAL32) that never loaded
    (`dll_absent=`).
    - Missing imports of Wine's own modules are `dll_missing_wine=`, recorded and not gated.
    - The case that prompted this: every session logs Wine's Indeo codec `ir50_32.dll` wanting `winegstreamer.dll`
      during Wine's codec scan (devenum → msvfw32). Neither this Wine nor the console runtime has winegstreamer,
      and the console runtime ships `ir50_32` too.
    - The user chose this definition on 2026-11-02, after the smoke run counted that line. The rule's text is
      unchanged.
  - `presents`: the last `PW_VK_BATCH` `present=`.
  - `save_new`: 1 when a file under a `SavedGame<N>` path (any depth, any case) in the game folder or in
    `drive_c/users` is newer than the session start.
  - `pad_reads`: the shim's reads of controller 0 while the pad was connected.
  - `session_s`: wall clock from launch to exit.
  - Every file the session wrote is listed at the end of the log and kept under
    `build/host-game/psychonauts-writes/<ts>/`.
  - `host-game.sh --parse LOG` prints the fields that come from the log; `check_psy_test.sh` tests that parsing.

**j result (2026-11-02): the rule passes, the restart check fails** (S3, resolved 2026-11-03 by patch 0904 below).

**Session A** (`logs/20261102-172728-host-psychonauts-j.log`, the user's copy, `--debug +keyboard`).
`check.sh j` gives `PASS (host)`:
`exe_base=0x00400000 dll_missing=0 presents=60149 save_new=1 pad_reads=181595 session_s=1028 fps_avg=58.5 crossings_per_frame=46 dll_missing_wine=1 dll_absent=- dxvk_conf=found steam_init=- exit=0 dumps=0 pad_first_read_ms=229 rumble_events=31 rumble=ok`.
- **The user's word:** main menu, New Game, the intro and cutscenes, then Raz in control at the camp for about
  10 minutes, then saved. Sound throughout. The d-pad works in menus. Nothing odd.
- **The pad:**
  - after Options → Bindings → Defaults, the buttons moved, jumped and turned the camera;
  - the bindings screen only ever shows keyboard keys;
  - the user felt no rumble (below).
- **Quitting:** the game cannot be quit from its menu here. It was closed by WM_CLOSE, sent from the game's own
  virtual desktop: `wine explorer /desktop=psychonauts,1920x1080 taskkill /im Psychonauts.exe`. Wine's `taskkill`
  without `/f` looks for windows only on its own desktop, so run from the default desktop it reports "not found".
  The game exited 0 and unloaded its DLLs.
- **Saves and profile:** `C:\Psychonauts\Profiles\Profile 1\`.
  - `SavedGame0`-`SavedGame6` are files of 61,439-61,440 B.
  - `Profile 1- Raz` (57 B).
  - `Profile 1- Raz.ini`: the bindings and the options.
  - Creating the profile at the first start writes all seven slots. So on a first launch `save_new=1` does not prove
    a save by itself.
  - Here the user's save is the separate write of `SavedGame1` (17:41:57); `SavedGame0` (17:30:01) is probably an
    autosave.
  - Copied to `build/saves/psychonauts/` (`--saves-out`).
  - k's profile key is `saves = C:\Psychonauts\Profiles`, not the inferred `WorkResource\SavedGames`.
  - Nothing was written under `drive_c/users`. A's guesses (`_getcwd`, the `%s\Profiles` migration) hold;
    `%LOCALAPPDATA%` is not used.
- **DLLs:**
  - Every DLL the EXE imports, and OpenAL32, loaded: native `AudioDrv`, `binkw32`, `isactwin`, `ogg`, `OpenAL32`,
    `steam_api`, `vorbis`, `vorbisfile`; builtin `MSVCR90` from winsxs, and the rest from system32.
  - `steam_api` loads and prints nothing; the game runs without Steam.
  - Wine's codec scan logs the `ir50_32` → `winegstreamer` miss (`dll_missing_wine=1`).
- **Other err lines:**
  - wined3d's GL context fails: something probes wined3d before DXVK takes d3d9.
  - "No software synthesizer midi port": AudioDrv calls `midiOut*`, and the sound still worked.
- **Frame rate:** 58.5 fps over the session, under `d3d9.maxFrameRate = 60`.

**Session B** (`logs/20261102-175028-host-psychonauts-j.log`, the restart; 242 s, so its own line fails j on
`save_new=0` and `session_s`, as expected).
- **The user's word:** after the restart the pad's buttons do nothing. Only the sticks work, and the menus need
  Space. The save loaded at the camp.
- The session wrote no file; `Profile 1- Raz.ini` is byte-identical before and after.
- **Wine bug 20834, confirmed on our Wine.** After session A the INI's pad column (`*_Alt`) holds keyboard names:
  `Jump_Alt=P`, `Attack_Alt=O`, `Use_Alt=]`, `Cancel_Alt=[`, `LockOn/Float_Alt=Enter`, `LookUp_Alt=F3`,
  `LookDown_Alt=F3`. Only `PsiPower1_Alt=Joy6` and `LookLeft/Right_Alt=JoyZ` survive.
  - The `+keyboard` trace shows how: the game passes its joystick codes to
    `MapVirtualKeyEx(code, MAPVK_VSC_TO_VK)` (`code 285/286/287`, i.e. 0x11d/0x11e/0x11f, about 13,000-21,000
    calls each).
  - winex11 matches only the low byte (`winex11.drv/keyboard.c`), so each code aliases a keyboard scan code. For
    example, 0x11d returns 0x11 (VK_CONTROL).
  - Defaults put the right codes back into memory, but the INI keeps the keyboard names, and the next start reads
    them back.
- **Not tested, inference from the source only:** the console has no driver `MapVirtualKeyEx` and falls back to
  win32u's generic path. That path reads 0x100-0x2ff as the extended scan-code table (`vsc2vk[0x300]`,
  `dlls/win32u/input.c:1286-1290`), so 0x11d becomes E0 1D (Right Ctrl) → VK_CONTROL there too. The console would
  mangle the pad column, though not necessarily into the same names. What Windows returns for these codes is not
  known here.
- **The keyboard column reads `MoveForward=Z/Q/S/D`, `PsiPower2=A`. This happens only on the host, and is not the
  bug:**
  - XWayland's keymap holds two groups, from KDE's `~/.config/kxkbrc` `LayoutList=be,us`: Belgian first, then
    `us(altgr-intl)`, which is the active group (`setxkbmap -query`: `us`). The keyboard is physically QWERTY.
  - winex11 detected both groups ("Belgian keyboard layout" for group 0, "United States" for group 1). It then
    translated the game's scan codes through group 0.
  - The console has the one US layout.

**Open after j:**
1. **The bindings (S3).** The plan's fallbacks need the user's go-ahead, and so does the order:
   - a Wine patch so `MapVirtualKeyEx(VSC_TO_VK)` returns 0 for codes that are neither plain scan codes nor
     0xE0/0xE1-prefixed (winex11 for the host, win32u's generic path for the console), tested here in j's setup;
   - psycho_fix's byte on a copy;
   - Defaults every session.
2. **Rumble not felt.** The shim sent 31 changes; `EVIOCSFF` and the `EV_FF` writes reported no error. Not yet
   measured: the magnitudes the game asked for, and whether the effect's `replay.length = 0` keeps a memless effect
   running.
3. **The touchpad (Back and the mark)** needs the user's udev rule; it was untested in A and B.
4. **j2** (headless, 4 KiB and 16 KiB pages) only on the user's word.

**The S3 fix: fork Wine patch 0904 (the user's choice, option 1, 2026-11-02).**
`wine/patches/0904-win32u-no-translation-for-scan-codes-above-0xff.patch`.
- **What it does:** at the top of win32u's `NtUserMapVirtualKeyEx`, before the driver, for `MAPVK_VSC_TO_VK` and
  `MAPVK_VSC_TO_VK_EX` only: a code whose bits above the low byte are not 0, 0xe000 or 0xe100 returns 0. One hunk
  covers winex11 (the laptop) and the generic path (the console, where ps5drv has no `MapVirtualKeyEx`).
- **Why it is not in winex11:**
  - `X11DRV_GetKeyNameText` (`winex11.drv/keyboard.c:2569-2572`) deliberately calls the driver with 0x1xx codes.
  - win32u's `map_scan_to_kbd_vkey` (`input.c:1329`, the keyboard input path) calls the driver directly and passes
    extended keys as 0xe0xx.
  - Every internal caller of `NtUserMapVirtualKeyEx` asks a VK_TO_* mode or masks to 0xff (`input.c:1396`,
    `ps5drv.c:607`, `wayland_keyboard.c:683`).
- **Sources for "Windows returns 0":**
  - Microsoft's MapVirtualKeyExW page (updated 2025-07-01), for both modes: "If there is no translation, the
    function returns 0." and "the high byte of the uCode value can contain either 0xe0 or 0xe1 to specify the
    extended scan code".
  - Wine's own `user32/tests/input.c:3297-3313` `test_key_map`, which passes on Windows: `0x011d`, `0x021d`, `0x136`,
    `0x137`, `0x237`, `0x145` → 0 under `_EX`, marked `todo_wine`.
  - **The game.** `Psychonauts.exe` 0x405b90, the key-name lookup:
    - it names a code by `vk_names[MapVirtualKeyExA(code, 1, layout)]` when that is nonzero and named;
    - otherwise by its own table, which holds the Joy names.
    - psycho_fix's byte (0x4F9F) skips that call. The patch clears those six todos and adds three type-1 rows; the
      user32 tests were not run (they inject keystrokes into the session).
- **Host test:** fork `tests/test_wine_mapvk.py` with `mapvk32.exe` (32-bit).
  - **Before the patch, both trees fail.**
    - drv (the console's generic path): 39 of 512 codes in 0x100-0x2ff translate, the first being 0x110 → 0xb1.
    - winex11: 214 of 512, the first being 0x101 → 0x1b (Escape).
  - **Key names recorded before the patch, required unchanged after it:** extended Right Arrow and Right Ctrl are
    `Right`/`Right_Ctrl` on drv and `Right`/`Control` on winex11.

**The restart proof, fixed before session C.** Sessions run on the user's copy with `--debug +keyboard` on the rebuilt
desktop Wine. Each is closed by WM_CLOSE from its desktop when the user says so.
- **Session C:** Options → Bindings → Defaults, once. The user checks that the pad's buttons work. Then
  `Profile 1- Raz.ini` is snapshotted, with its pad column recorded.
- **Sessions D and E:** restarts, no Defaults.
- **Pass, all of:**
  - the user's word that the pad's buttons work in D and E without Defaults;
  - `Profile 1- Raz.ini` byte-identical after C, D and E (`cmp`);
  - after C, the `*_Alt` entries that held keyboard names in B (`Jump`, `Attack`, `Use`, `Cancel`, `LockOn/Float`,
    `LookUp`, `LookDown`) hold none;
  - `mapvk_high=N/0` in C, D and E (`host-game.sh` with `+keyboard`; before the patch, session A gave 62910/62904
    and B 7676/7667).
- **On a fail:** stop and report; change nothing else.
- **Then j passes.** The console gets 0904 with i's package and its regressions.

**The restart proof passed (2026-11-03).** All sessions ran on the rebuilt desktop Wine (0904 in it), on the user's
copy, with `+keyboard`, and were closed by WM_CLOSE.

| Session | Log | What the user did | INI | `mapvk_high` | User's word |
|---|---|---|---|---|---|
| C | `logs/20261103-002505-host-psychonauts-j.log` | Options → Bindings → Defaults, once | written by the game at 00:26:30, inside the session (it started 00:25:05 and exited 00:29:03); snapshot `after-C.ini` | 20116/0 | the pad works |
| D | `logs/20261103-003111-host-psychonauts-j.log` | restart, no Defaults | byte-identical to C (`cmp`), still written at 00:26:30 | 19168/0 | the buttons worked straight away |
| E | `logs/20261103-003443-host-psychonauts-j.log` | restart, no Defaults | byte-identical to C | 30818/0 | the buttons worked again |

- **The pad column after C**, where B had keyboard names: `Jump_Alt=Joy2`, `Attack_Alt=Joy1`, `Use_Alt=Joy4`,
  `Cancel_Alt=Joy3`, `LockOn/Float_Alt=Joy5`, `PsiPower2_Alt=Joy7`, `PsiPower3_Alt=Joy8`, `InventoryMenu_Alt=DPadLeft`,
  `PsiPowersMenu_Alt=DPadRight`, `FirstPerson_Alt=Joy12`, `Journal_Alt=Joy9`, `Stats_Alt=Joy11`,
  `LookUp/LookDown_Alt=JoyRotZ`.
- **The mouse buttons came back too:** `Attack=LeftMouse` and `PsiPower1=RightMouse`, where A had written `1` and
  `2`. Their codes are above 0xff as well.
- **The INI was never edited by hand.** Each session wrote only the DXVK cache, apart from C's INI and profile
  writes.
- **Snapshots** are in `build/host-game/psychonauts-ini/{before-C,after-C,after-D,after-E}.ini`.
- **Mono and Gecko in the user's prefix.** The first launch on the rebuilt Wine (C) ran Wine's prefix update through
  `host-game.sh`'s setup check, which did not disable them, so `build/prefix-desktop-psychonauts` now holds Wine Mono
  and Gecko. Both setup commands now set `mscoree,mshtml=`. The game uses neither.
- **Fresh profile** (the test copy, which had no profile before): see "Found in j" under l.

**Not tested:** the console's driver, audio path, pad source and memory. 16 KiB pages only as emulated.

**Stop point S3.** If the game fails on the host for a reason that is not the console's (a crash, no sound, steam_api
fatal, bindings unusable), fix it on the host first. No console upload until j passes.

**Commit** fork and repo after j passes (the user commits).

### k: Psychonauts' main menu on the PS4 with sound (like g2)

**Precondition:** i and j passed. The user reads Settings → Storage: at least 6 GB free on /data (FTP and statfs cannot
tell).

**Repo:**
- `profiles/psychonauts.ini`:
  - exe `C:\Psychonauts\Psychonauts.exe`, working directory `C:\Psychonauts`, no arguments;
  - `d3d9=n`, desktop 1920x1080, `show_fps = true`;
  - `[input] preset = psychonauts`;
  - `cpu = native`;
  - `saves = C:\Psychonauts\WorkResource\SavedGames` (j's measured path);
  - `DXVK_CONFIG_FILE=C:\Psychonauts\dxvk.conf` in its environment.
- `profiles/psychonauts.dxvk.conf`: `d3d9.maxFrameRate = 60`. `game.sh` uploads it as `C:\Psychonauts\dxvk.conf`.
- `profiles/input/psychonauts.input`: keys for the menus until l.
- `scripts/ps4/game.sh --game vtmb|psychonauts` (default `vtmb`): a per-game table of source, destination, excludes
  (French/German), the INIs into the game root, the manifest `build/game-psychonauts.manifest`, and the save glob.
- `check.sh k`.

**Fork title:**
- Plan g's machinery generalised. Plans k, l, m and n take the profile id from env.txt `PS4WINE_PROFILE`, defaulting
  per plan (g → vtmb, k-n → psychonauts), and the line word is that id.
- Plan k runs g's stages: cpu_probe, wow_bind, display, audio, game.
- `pw_game_profile.c` reads the new `saves` key.

**Rule `check.sh k`:**
`PS4WINE k psychonauts menu=1 exe_base=0x00400000 eboot_release=ok audio=on grains_nonzero>=10 audio_errors=0 faults_unresolved=0 exit=running`.
- `menu=1` is the user's first mark on the main menu.
- Plus the recording's audio over the menu window, mean ≥ -30 dB (p5's D, measured against two silent recordings), via
  `check.sh k --audio WAV --audio-window S:D`.
- Plus an HDMI frame of the menu as evidence.

**One launch with `+loaddll` tests at once:**
- the EXE at 0x400000;
- every DLL;
- Bink's intro;
- OpenAL → dsound → wineps5;
- DXVK with no app profile, capped by our `dxvk.conf`;
- `flex_mib_min`, `dmem_peak_mib`;
- the time from launch to the menu.

**Regressions:** the plans changed, so g1n, g1m, g1, e and g2 run on the k package first.

**Not tested:** gameplay, the pad in the game, saves, long sessions.

**Stop point S4.** If `audio=on` but `grains_nonzero=0`, or the menu window is silent, measure DirectSound's timed wait
(ORBIS-WIN row 4) before more launches.

**Commit** fork and repo after k passes (the user commits).

### l: the DS4 in Psychonauts as XInput controller 0

**Found in j (2026-11-03): the first launch needs Enter on the PS4.**
- The new-profile screen (the bunk bed and the name) takes only Enter and Esc from the keyboard; the pad cannot
  confirm it. On the PS4, with no keyboard, that blocks a first launch.
- The pad works elsewhere on a fresh profile: Circle skipped the first dialogue (the user's word, from the
  fresh-profile check on the test copy). That run wrote no profile file before its 300 s limit, so the INI a fresh
  profile writes under patch 0904 was not read.
- **l adds, in xinput mode:** DS4 buttons that also send Enter and Esc for text screens, through the title's key
  posting (plan g's mapper, which in xinput mode posts key edges beside the pad, as on the PS5:
  `wine64_main.c:1597-1609`).
- **Constraints from the INI after Defaults:**
  - Escape is bound to `Journal` in gameplay. An Esc button must be the button the pad already uses for the Journal
    (`Journal_Alt=Joy9`), or one with no gameplay use.
  - Enter is unbound in gameplay (`LockOn/Float_Alt` is `Joy5` after 0904), so Enter can share a confirm button.
  - Which DS4 button is `Joy9` gets read from the game's Options screen in l.
- **The bonus idea, not planned:** the PS4 user's name (`sceUserServiceGetUserName`) as Wine's user name, so the
  name screen fills itself in. It cannot work for this game: `Psychonauts.exe` imports no ADVAPI32 (so no
  `GetUserNameA`) and has no `USERNAME` string. Its only possible name source is steam_api's `SteamFriends`, which
  needs Steam. The idea is kept for games that read the Windows user name.

**Changes:**
- `profiles/psychonauts.ini` `[input] mode = xinput`; the touchpad as in l1.
- If j showed garbled bindings: a fork Wine patch so `MapVirtualKeyEx` answers the game's codes as Windows does. It is
  PE-side, tested on the host in j's setup, and a runtime change (regressions follow).
- Fallback, only with the user's go-ahead: psycho_fix's one byte (file offset 0x4F9F, 74 → 75), applied by `game.sh` to
  the console copy. `games/` is never written.

**Rule `check.sh l`:**
`PS4WINE l psychonauts input=xinput pad_connected_at_start=1 pad_reads>=1 kbm=0 faults_unresolved=0 exit=running`.
- `pad_reads` is the sink's `pads_wanted` for slot 0.
- Plus the user's word: the main menu works with the pad; Raz walks, jumps and turns the camera; a second launch shows
  the same bindings.

**Console launches:**
1. The game with the pad.
2. A second launch, for the restart check.

**Not tested:** rumble in the game (recorded), long sessions.

**Stop point S5.** If the game never reads XInput (`pad_reads=0` with the pad connected at start), stop. The fallback is
plan g's keyboard mapper with a Psychonauts preset (DS4 → keys); decide it with the user.

**Commit** fork and repo after l passes (the user commits).

### m: gameplay reached, 300 s (like g)

**Changes (title):** plan m reuses g's window maths, marks, `PW_VK_BATCH` parsing, `fps_avg` and recorded fields.

**Rule `check.sh m`:**
`PS4WINE m psychonauts batch=1 gameplay=1 input=xinput kbm=0 crossings_per_frame<=2000 fps_avg>=30 fps_avg<=61 session_s>=300 faults_unresolved=0`.
- `gameplay=1` is the user's mark with Raz in control, after New Game and the intro. The window starts there and the
  user stays in the area.
- Plus an HDMI frame as evidence.
- Recorded:
  - `flex_mib_min`, threads, `dmem_peak_mib`, `heaps_mib`, `dxvk_oom`;
  - `frame_us_avg/p95/max`, `hitches_50ms`;
  - `underruns`, `grains_nonzero`.

**One launch** tests New Game, the intro and first cutscenes (D's crash report), the first level's load, and 300 s of
play.

**Not tested:** 30 minutes, save and load, later levels.

**Stop point S6.** If `fps_avg<30`, record the numbers (the line's recorded fields in LOG.md and HANDOFF-i) and park
Psychonauts at m, as Bloodlines is parked at g. No profiling round in this plan. The threshold is never moved.

**Commit** fork and repo after m passes (the user commits).

### n: playable, 30 minutes with a save and a load (like h)

**Changes:**
- The title polls the profile's `saves` directory every 5 s (stat on /data).
  - `saved=1` when a file there changes after the gameplay mark.
  - `loaded=1` is the user's mark after loading a save (any mark after `saved=1`). It is the user's word, not verified
    from the file system.
- `check.sh n` lists the save directory over FTP and requires a file newer than the session start. This also implements
  h's TODO generically.

**Rule `check.sh n`:**
`PS4WINE n psychonauts session_s>=1800 fps_avg>=30 fps_avg<=61 input=xinput kbm=0 saved=1 loaded=1 audio=on audio_errors=0 faults_unresolved=0`.
- Plus the FTP save check.
- Plus the user's word: started from the PS4 menu, played with the DS4 alone, sound throughout.

**One launch:** about 35 minutes.

**Not tested:** rest mode during play (recorded if it happens), later levels (Meat Circus ...), sessions past 30
minutes.

**Commit** fork and repo after n passes (the user commits).

### Later (not planned here)

- The game picker: one title that lists the profiles on `/data/ps4-wine/profiles` and starts the chosen game.
- Bloodlines' resume list (`HANDOFF-g.md`, "Next session").

## Research findings

Desk research 2026-11-02, read-only: nothing built or run. F = `third_party/prospero-win`, R = repo root.

### A. The installer and the game files

Read-only: listings, header reads and small members (EXE, DLLs, INIs) extracted to a session scratchpad before the
extraction. Nothing was written to the console.

**Tooling.** `innoextract --info`: "Psychonauts", setup data 5.5.0 (unicode), innoextract 1.9, languages english,
german, french, GOG id 1207658807. `unar -i <idx> -o DIR` on `-1.bin` extracts nothing (also with `-s`); by member name
without `-s` it works; `unar -o -` streams by index. 7z 26.00 lists both volumes but cannot unpack (no RAR codec).

**Inno side** (`innoextract --list`): 110 `[temp]` files (installer UI, `botva2.dll`, `crcdll.dll`, `get_hw_caps.dll`,
`InnoCallback.dll`, `unrar.dll`), one real file `app/GameuxInstallHelper.dll` (94 KiB), and the warning that `-1.bin`
and `-2.bin` need `--gog`. No redistributables (no `__redist`, no DirectX or VC runtime).

**RAR side** (`innoextract --list --gog`, sizes from `lsar -j`):
- Not encrypted: every entry `"Encrypted": 0`, no password flag (0x04). (innoextract's man page: the password would be
  the MD5 of the game id, `md5(1207658807)` = `c371090420b0e0b66703e851cb0e9867`.) No solid entries (flag 0x10); 7z
  reports `Solid = -`, `Multivolume = +`, `Volumes = 2`.
- One file spans both volumes: `game/WorkResource/Sounds/commonfx.isb` (flags 0x80c2 in -1, 0x80c1 in -2).
- **1774 files, 38 directories, 5,510,306,912 B (5.132 GiB) uncompressed**, 4,289,185,413 B compressed.
- Extracted top level: `__unpacker/`, `game/`, `support/app/`, plus Inno's `app/`. The game is under `game/` (Bloodlines
  had it at the root).

| Path | Files | Bytes |
|---|---|---|
| `game/WorkResource/Sounds` | 199 | 2,428,213,818 (French 730,020,076; German 731,892,024) |
| `game/WorkResource/cutscenes` | 170 | 1,817,327,282 |
| `game/WorkResource/PCLevelPackFiles` | 100 | 1,066,663,671 |
| `game/WorkResource/VertexShaders` | 1065 | 1,711,458 |
| `game/WorkResource/Localization` | 140 | 3,283,079 |
| `game/WorkResource/{Fonts,PixelShaders,Scripts,Textures,SAVEDGAMES}` | 8 / 59 / 1 / 1 / 1 | 803,312 / 13,028 / 402,486 / 9,153 / 62 |
| `game/Psychonautsdata2.pkg` | 1 | 151,566,336 |
| `game/` root: EXE, DLLs, `Language Setup.exe` (16,886,368), manual PDF (6,995,429), goggame files, `webcache.zip`, `Documents/` (6) | 23 | ~32 MB |
| `support/app/*.ini` | 3 | 402 |
| `__unpacker/__unpacker.gog` (a JPEG, `FF D8 FF E0`) | 1 | 8,368,984 |

French + German sound is 1,463,351,352 B, so an English-only set is ~4.05 GB (that the game skips those folders in
English is inference, to verify in j).

Largest files: `cutscenes/prerendered/INTRO.bik` 163,209,972; `ASCA.bik` 156,728,656; `Psychonautsdata2.pkg`
151,566,336; `FINI.bik` 100,478,524; `Sounds/German/thvoice.isb` 97,478,704; `Sounds/thvoice.isb` 96,066,446;
`Sounds/French/thvoice.isb` 96,036,040; `Sounds/German/cavoice.isb` 64,541,278; `Sounds/French/cavoice.isb` 63,422,038;
`Sounds/cavoice.isb` 62,972,600. Volume 2 holds `Psychonauts.exe` (idx 1085), `binkw32.dll` (1086), `AudioDrv.dll`
(1087), `goggame-1207658807.info` (1088), `ogg.dll` (1089), `support/app/{DisplaySettings,AudioSettings,Psychonauts}.ini`
(1090-1092); volume 1 every other DLL and `Language Setup.exe`.

**Play tasks** (`goggame-1207658807.info`): primary `"path": "Psychonauts.exe"`, `"workingDir": ""` (the game folder),
no arguments; "Language Settings" → `Language Setup.exe`; support tasks: a URL, the manual PDF, `ReadMe.txt`;
`standalone: true`, `language: english`.

**PE images** (`python3 -I scripts/ps4/pe_bases.py`, exit 1 for the blocked fixed image; all i386):

| Image | ImageBase | End | Relocs stripped | Reloc dir | Relocatable |
|---|---|---|---|---|---|
| `Psychonauts.exe` | 0x00400000 | 0x0080c000 | yes (no `.reloc`) | 0 | **no** |
| `Language Setup.exe` | 0x00400000 | 0x01431000 | no | 277424 | yes |
| `AudioDrv.dll` | 0x10000000 | 0x1002c000 | no | 5548 | yes |
| `isactwin.dll` | 0x10000000 | 0x10050000 | no | 9356 | yes |
| `OPENAL32.dll` | 0x10000000 | 0x101cb000 | no | 6588 | yes |
| `vorbis.dll` | 0x10000000 | 0x10108000 | no | 12072 | yes |
| `vorbisfile.dll` | 0x10000000 | 0x10011000 | no | 1748 | yes |
| `ogg.dll` | 0x10000000 | 0x10009000 | no | 992 | yes |
| `goggame-1207658807.dll` | 0x10000000 | 0x10047000 | no | 1748 | yes |
| `binkw32.dll` | 0x30000000 | 0x30068000 | no | 20216 | yes |
| `steam_api.dll` | 0x3b400000 | 0x3b41e000 | no | 4172 | yes |
| `DbgHelp.dll` | 0x59a60000 | 0x59b01000 | no | 29260 | yes |
| `app/GameuxInstallHelper.dll` (Inno) | 0x00400000 | 0x0041a000 | no | 2868 (DYNAMIC_BASE) | yes |

Verdict: only `Psychonauts.exe` is fixed, and it covers the eboot's whole range; seven DLLs want 0x10000000 and are moved
by Wine; no two fixed images overlap.

`Psychonauts.exe` (`x86_64-w64-mingw32-objdump -p -h`): Characteristics 0x103, ImageBase 0x400000, SizeOfImage
0x40c000, empty relocation directory, no `.reloc`; PE32, linker 9.0 (VS2008), timestamp 2016-01-06, version 1.1.603.0
("Psychonauts PC", Double Fine), 4,150,272 B; entry 0x6ed79f; GUI; DllCharacteristics 0x8000 (no DYNAMIC_BASE, no NX);
stack reserve 1 MiB; load config present; no TLS directory.

| Section | VA | VirtSize | RawSize | Characteristics |
|---|---|---|---|---|
| `.text` | 0x00401000 | 0x2fad9f | 0x2fae00 | 0x60000020 (RX) |
| `.dfluatx` | 0x006fc000 | 0x003d4e | 0x003e00 | 0x60000020 (RX) |
| `.rdata` | 0x00700000 | 0x07d432 | 0x07d600 | 0x40000040 (R) |
| `.data` | 0x0077e000 | 0x01815c | 0x004000 | 0xc0000040 (RW) |
| `.dflua` | 0x00797000 | 0x00ae64 | 0x00b000 | 0xc0000040 (RW) |
| `.rsrc` | 0x007a2000 | 0x069c4c | 0x069e00 | 0x40000040 (R) |

Three 16 KiB pages mix protections (computed from the table): 0x400000-0x404000 (headers R + `.text` RX),
0x77c000-0x780000 (`.rdata` R + `.data` RW), 0x7a0000-0x7a4000 (`.dflua` RW + `.rsrc` R). `WINE_HOST_PAGE_SIZE=16384`
reproduces it on the host.
- Corrected 2026-11-02: these pages are not handled by patches 1120/1130, which fix decommit, clear and the hot
  host page of private memory.
- An image's mixed host page gets the union of its pages' protections, by patch 0974 (its `SEC_IMAGE` branch,
  0974:179).
- 0974 is read by ntdll and by wineserver alike, so `wineserver -k` is needed between page sizes.
- No fixed-base PE32 image has run at 16 KiB yet (j2 and i's `fixed32.exe` would be the first).

**Imports of `Psychonauts.exe`.** `DINPUT8` (`DirectInput8Create`); `d3d9` (`Direct3DCreate9`); `d3dx9_40` (15:
`D3DXCompileShader`, `D3DXAssembleShader`, `D3DXGetShaderConstantTable`, `D3DXCreateBuffer`, `D3DXFilterTexture`,
`D3DXSaveSurfaceToFileA`, matrix/quaternion/vector maths); `WINMM` (`timeGetTime`); `DSOUND` (ordinal 1 =
`DirectSoundCreate`); `binkw32` (`_BinkOpen@8`, `_BinkClose@4`, `_BinkDoFrame@4`, `_BinkNextFrame@4`, `_BinkWait@4`,
`_BinkCopyToBuffer@28`, `_BinkSetSoundSystem@8`, `_BinkOpenDirectSound@4`, `_BinkSetSoundTrack@8`, `_BinkGetTrackID@8`,
`_BinkSetVolume@12`); `isactwin` (ordinal 2 = `RetrieveISACTInterface`); `AudioDrv` (ordinal 3 =
`RetrieveISACTRenderInterface`); `XINPUT1_3` (ordinals 2, 3 = `XInputGetState`, `XInputSetState`); `steam_api`
(`SteamAPI_Init`, `_Shutdown`, `_RunCallbacks`, `_RegisterCallback`, `_UnregisterCallback`, `_WriteMiniDump`,
`SteamRemoteStorage`, `SteamFriends`, `SteamUserStats`); `KERNEL32` (68), `USER32` (36), `SHELL32` (`SHGetFolderPathA`),
`ole32` (`CoInitialize`, `CoCreateInstance`, `CoSetProxyBlanket`, `CoUninitialize`), `OLEAUT32` (ordinals 2, 6-9),
`MSVCR90` (138). One `LoadLibraryA("OpenAL32.dll")` (string at 0x71d5d0). Manifest: `Microsoft.VC90.CRT` 9.0.21022.8
(x86). `d3dx9_40`, `msvcr90`, `xinput1_3` are not shipped: our runtime's `build/runtime/win/wine/lib/wine/i386-windows/`
has builtin `d3dx9_40`, `msvcr90`, `xinput1_3`, `dsound`, `dinput8`, `d3d9`, `winmm`, `dbghelp`; no `openal32` (the
game ships its own).

**Shipped DLLs.**
- `steam_api.dll`: Valve's real one, 1.14.66.23, Authenticode-signed, 0x38 exports; reads `Software\Valve\Steam` and
  `...\ActiveProcess`, wants `steamclient.dll`; "[S_API FAIL] SteamAPI_Init() failed". Without Steam `SteamAPI_Init`
  returns false; the EXE caches the result at 0x534680.
- `binkw32.dll`: RAD Bink 1.6e (1.6.4.0); imports USER32, GDI32, KERNEL32, WINMM (waveOut); names `DSOUND.DLL`,
  `MSS32.DLL`, `DDRAW.DLL` (run-time loads, presumably).
- `isactwin.dll`: Creative ISACT runtime 1.5 (© 2005); KERNEL32 only; exports `RetrieveISACTInterface`; names
  `vorbisfile.dll`.
- `AudioDrv.dll`: Creative AudioDrv 1.5, the ISACT renderer; exports `InitAudioDriver` (2), `RetrieveISACTRenderInterface`
  (3); **imports OpenAL, not dsound**: `OpenAL32.dll` (34: `alcOpenDevice`, `alcCreateContext`, `alGenSources`,
  `alSourceQueueBuffers`, `alIsExtensionPresent`, `alGetProcAddress` ...), WINMM (`midiOut*`, `timeSetEvent`,
  `timeKillEvent`, `timeGetDevCaps`), KERNEL32; strings `EAX4.0`, `EAX4.0Emulated`, `EAXGet`, `EAXSet`.
- `OPENAL32.dll`: Creative 1.09, "Creative DS3D Wrapper Implementation"; imports WINMM (waveOut), USER32, ole32
  (`CoCreateInstance`, likely DirectSound); strings `DirectSound3D`, `EAX2.0`-`EAX4.0`, `eaxac3.dll`.
- `ogg.dll`, `vorbis.dll`, `vorbisfile.dll`: codecs. `DbgHelp.dll`: XP 5.1.2600.2180, imported by nothing shipped.
  `goggame-1207658807.dll`: a Game Explorer resource DLL, not loaded. `Language Setup.exe`: Qt (OpenGL32, msvcrt).

**Settings, saves, command line.**
- `support/app/DisplaySettings.ini` `[DisplaySettings]`: `ScreenWidth=1920`, `ScreenHeight=1080`, `FullScreen=true`,
  `VSync=true`, `FSAA=true`, `FSFX=true`, `AdvancedShading=true`, `Shadows=true`, `GammaCorrection=1.000000`.
  `AudioSettings.ini` `[AudioSettings]`: volumes 1.0, `ShowSubtitles=true`, `HardwareAccel=true`, `UseEAX=false`,
  `PacketSize=250`, `MusicPacketSize=375`, `PreloadVoice=true`. `Psychonauts.ini`: `language english` (16 B). CRLF.
  `WorkResource/SAVEDGAMES/savegameprefs.ini`: `player.stats`, `saved`.
- No registry use in the EXE (only `steam_api.dll` reads Valve keys).
- **The settings folder is the working directory:** `_getcwd` at 0x535c91, then `%s\DisplaySettings.ini` (0x70bcc0),
  `%s\AudioSettings.ini` (0x70b138). So the INIs belong in the game folder.
- **Saves** (function at 0x6a88b0): under Cider on macOS `SHGetFolderPathA(CSIDL_LOCAL_APPDATA)` + `\Psychonauts`,
  otherwise `_getcwd`; with a successful `SteamAPI_Init` an extra step at 0x534840 (not traced). Paths
  `d:\workresource\savedgames\savemeta.xbx`, `%s\SavedGame%d` (7 slots, loop at 0x55174d), `SavedGames\savegameprefs.ini`,
  `%s\%s.ini`. So without Steam saves should land in `<game>\WorkResource\SavedGames\` (inferred, to measure in j).
- `../psychonauts.ini` read at 0x4f7ea7, beside developer keys `sound`, `main_menu`, `ingame_menu`, `debug_server`,
  `start_log`, `no_hud`, `attractmode` (base of `..` unknown). Also `WorkResource\Textures\icons\UI_Icons\IconPrefsPC.ini`,
  `PsychonautsData2.pkg`, mutex `PsychonautsGameMutex`, "Failed to find Psychonauts CD - please insert disc".
  `GetDiskFreeSpaceA("C:\")` at 0x6a8a49, result ignored.
- Command line (parser at 0x5364b0): `-width N`, `-height N`, `-refresh N`, `-fullscreen`, `-antialias`, `-nosound`; no
  `-windowed`.
- Controls: XInput 1.3 get and set (rumble) plus DInput8; labels `/Joy1/`-`/Joy32/`, `/FullMouse/`, `JOY_A`; key table
  at 0x77f5e0 (`InvertCamVert`, `InvertCamHoriz`, `InvertFPCam`, `SmartCamera`, `CameraAltitudeDampening`,
  `EnableRumble`, `ShowGoalPopups`, `MouseSensitivity`, `JoystickDeadzone`); classes `EBindingsSettings`,
  `EKeyboardBindingsWidget`, `EControllerPage`, `EGameSettingsList`. Where bindings are stored is not determined
  (probably a profile beside the saves, `Profile` at 0x70eb24).

**DXVK 2.6.2.** No Psychonauts entry: `x32/d3d9.dll` in `build/downloads/dxvk-2.6.2.tar.gz` has `\\vampire\.exe$` and
nothing matching "sychonaut"; `https://raw.githubusercontent.com/doitsujin/dxvk/v2.6.2/src/util/config/config.cpp` (1635
lines) has no "sychonaut" or "double fine" (Vampire at :575-576; the URL HANDOFF-g read).

**Console /data space.** No earlier measurement. statfs/fstatfs are ENOSYS for a title
(`F/wine/orbis/include/sys/mount.h:6-7`, `F/docs/WINE_PS5_BUILD.md:904`). FTP (logged in as `runtime.sh:90-91`):
`du -sb /data/ps4-wine/prefix/drive_c/VTMB` = 4,310,145,998 B (the local manifest: 4,309,273,049 B over 20,981 files);
`du -sb /data/ps4-wine` = 5,096,744,725 B (4 × "550 File unavailable", so slightly low). Free space is not readable
over FTP: FEAT has MDTM, MLST, REST, SITE CHMOD, SITE UMASK, SIZE; `AVBL` 502, `SITE DF`/`SITE HELP` 504, `STAT` 502. The
user reads Settings → Storage. Need: ~4.05 GB (English) or 5.51 GB (all) on top of the 5.10 GB there.

**Unknown.** Free space; whether the game runs when `SteamAPI_Init` fails; the Steam branch at 0x534840; where bindings
are saved; the base of `../psychonauts.ini`; the exact save path; whether the installer copies `support/app/*.ini` into
the game folder and whether `get_hw_caps.dll` rewrites the resolution; whether French/German can be left out; which
DLLs `binkw32`/`isactwin` load at run time; whether `innoextract --gog` reassembles the split `commonfx.isb`.

### B. Row 16 in detail: orbis-win's low base mapped onto our title

Prefixes: `O` = `refs/orbis-win` (@ 2610706); `H10-14/20/26` = `O/docs/HANDOFF-2026-10-{14,20,26}.md`; `FIND` =
`O/docs/FINDINGS.md`; `S0300` = `O/src/prospero-win-patches-ps4/0300-pre-mdk-source-snapshot.patch`. Labels: code,
measured (a console log or probe output in their docs or ours), claimed, inference (ours).

**Two corrections to our own docs.**
- `ORBIS-WIN.md` F14: "a high PRX can release and reuse 0x400000" is not a lowbase-probe result: `O/src/lowbase-probe/
  README.md:14-20` is an expected sequence, and no probe output exists in their docs or git log. The proof is their
  Wine runs that loaded EXEs at 0x400000 after the release.
- `ORBIS-WIN.md` row 16: "0x400000-0x55c000" is a constant in their code (the old full title's end, FIND:2379; their own
  note says it "should be derived", H10-26:5264-5268). On the console their stub's r-x segment was 0x400000-0x49c000
  (vmprobe 1045, H10-26:5007-5010), and the release unmapped all three stub segments (H10-20:2323-2324, measured).
- Also stale: `HANDOFF-f.md:55-59` and `pe_bases.py`'s `EBOOT = (0x400000, 0x650000)`. Our eboot grows: 0x400000-0x650000
  in f1 (`logs/20261101-155320-f1.log` `low_map`), 0x400000-0x6bc000 in g1n (`logs/20261102-000719-g1n.log:657-660`),
  and the current `build/title/eboot.elf` spans 0x2c96d8 → 0x400000-0x6cc000 (computed). It holds 1,318,952 bytes:
  `.text` 0x8c2de (574 KB), R E PT_LOAD 0x8ca90, R 0x43df8, RELRO 0x81f8, RW filesz 0x4a10 memsz 0x1e96d8 (`.bss`
  0x1e4cc8, 1.9 MiB), PT_TLS memsz 8 (musl's locale). Nothing else is mapped below 4 GiB (`low_maps=3`).

**Their stub eboot** (`O/src/reloc-wine-app/stub.c`, code unless marked).
- Links `-lSceNet -lSceAudioOut -lSceSystemService -lSceSysmodule -lSceGnmDriver -lSceVideoOut -lScePad
  -lSceUserService` (`O/scripts/build-relocatable-wine-ps4.sh:101-105`). Required: a Sony library the PRX names in
  DT_NEEDED must already be loaded by the eboot; package 10110 failed `app PRX load failed` because the stub lacked
  libSceSysmodule (H10-20:3362-3372, measured). An eboot's DT_NEEDED on an app PRX is not loaded (FIND:1945-1950,
  measured).
- `main` (after a libkernel symbol diagnostic we do not need, `stub.c:80-152`) calls
  `sceKernelLoadStartModule("/app0/sce_module/relocated_wine_app.prx", 0, NULL, 0, NULL, &result)` (`:199-200`), reads
  the module's segments with `sceKernelGetModuleInfo` (info size 0x160, count at +0x148, segments at +0x108 + i*16,
  `:154-175`), finds the `PRXDESC1` descriptor (`:177-193`), looks up `pw_relocated_wine_start` (`:213-216`) and calls
  `entry(argc, argv)` on the main thread (`:222`). It never returns; failures idle in `sceKernelUsleep` (`:207, 219, 223`).
- It calls no `module_start`; their prospero-clang link differs. Ours must call it (`CLAUDE.md`, PRX recipe).
- argc/argv must be forwarded: GLDS10045 dropped them and the restarted process came back to the launcher; GLDS10046
  forwards them (H10-14:35-45, measured).

**Their PRX.** Every object of the ordinary title build (`O/scripts/build-app-ps4.sh:84-128`) except `pw_wine_prx.o` and
`native_wine64_main.o`, plus `wine64_main.c` with `-DPW_RELOCATABLE_WINE`, `app_entry.o` and a descriptor exporting
`pw_relocated_wine_start` (`build-relocatable-wine-ps4.sh:60-85`); linked `-shared -Bsymbolic -soname
relocated_wine_app.prx`, `create-fself -lib ... -libname relocated_wine_app.prx -ptype fake` (`:86-99`), packaged at
`sce_module/relocated_wine_app.prx` (`:109`), both images checked ELF DYN (`:128-130`). `pw_relocated_wine_start`
(`app_entry.c:81-88`) calls the title's `main` and idles if it returns. Their PRXs load at 0x800000000 (FIND:2422-2423,
claimed); ours measured: ntdll seg0 at 0x8008b4000 (`logs/20261030-030024-c.log:120`).

**The release.** `pw_relocated_wine_release_eboot()` (`app_entry.c:54-79`) re-reads module 0's segments (`:31-52`) and
`sceKernelMunmap`s every segment overlapping 0x400000-0x55c000 (`:12-13`, `:64-76`), returning the first nonzero rc.
Call site (patch `O/src/reloc-wine-app/0001-delay-eboot-release-until-game-start.patch:7-12, :20-28`, reapplied as
S0300:115-127, :210-218): a weak extern, called in `main` after `pw_wine_start_environment` and before
`pw_wine_start_run`, only when a game is set (the launcher never releases); a failure is `PW_ERR_STATE` and Wine does
not start. It runs on the main thread, which then runs the PRX's main loop (pad, present, `sceGnmSubmitDone`,
S0300:222-305).
- **Why it was delayed (measured):** GLDS10044 released before main and "immediately SIGSEGVed in `sceVideoOutOpen`,
  reading the unmapped eboot data address `0x4a0000`" (H10-14:32-34). Their comment: "Sony's display setup reads from the
  eboot's low data segment" (`app_entry.c:1-4`, claimed). Inference: 0x4a0000 is the first 16 KiB boundary after the
  stub's r-x end; in our ELF `.data.sce_process_param` sits on such a boundary (0xe4000, 16 KiB aligned), so the first
  `sceVideoOutOpen` probably reads the process param. A later open works once the first came before the release: RADV's
  WSI opens VideoOut at swapchain creation (`refs/mesa-ps4/src/vulkan/wsi/wsi_orbis.c:287`), after the release, and
  their Oblivion presented 1920x1080 (H10-20:2328, H10-14:7111-7121) (inference from measured runs).
- **How Wine learns the range is free: it does not need to.** The release precedes `pw_wine_start_run` → `__wine_main`
  → `virtual_init` → `mmap_init` → `reserve_area(0x10000...)`, which then takes the freed range. Their refused
  reservation (Fallout relocated, Oblivion c0000018) is at H10-26:4962-4972, retracted at H10-26:5002-5035: the occupant
  was the eboot (measured). Their WP/1010 (`O/src/wine-patches-ps4/1010-ntdll-ps4-reserve-diagnostics.patch:4-31,
  :64-151`) adds only a diagnostic and a fallback. The PE then maps at its base: Oblivion at 0x00400000 (H10-20:2326,
  H10-14:8497, measured).

**What they measured (PS4 Pro, FW 9.60, base mode).**
- PE32s at 0x400000 after the release: Oblivion.exe (relocs stripped, H10-26:5253-5258; H10-14:2443-2444) loaded and ran
  (H10-20:2322-2334; H10-14:8497); FalloutNV.exe on 19 consecutive runs (H10-26:5026); TQ.exe (H10-20:1695).
- Oblivion gameplay: ~4 fps on the translator (H10-14:8503-8521), 35-50 fps native (H10-14:7127-7134); after the release
  was restored in package 1046: loads, presents, audio, save loads (H10-26:5069-5072, :5669).
- Sessions after the release: ~2 min (closed by the user, H10-14:65-69), ~3m35s and ~4m15s (H10-14:3151-3160,
  :3187-3189), one still presenting at present #26400 (H10-14:7108-7134; ≥ ~18 min, our estimate). Nothing beyond tens
  of minutes.
- Closing from the PS menu after the release: "normal shell suspend/kill ... not a title crash" (H10-14:67-69, :3158-3160,
  :3188-3189).
- Crash reporting works: coredump `proc name: eboot.bin`, backtrace with `relocated_wine_app.prx main` and
  `runOnItsOwnAltStack` (H10-14:2212-2219); dumps retrieved (H10-14:2401-2414); the stack walk warned `copyin: orbis has
  nonsleeping lock` (H10-14:2424).
- After the release: app PRX loads (all of Wine), threads, netlog, VideoOut, AudioOut, pad, `sceGnmSubmitDone`
  (H10-26:176). Return to the launcher after a game exit (H10-20:2892, :4483; that it was LoadExec after the release is
  inference).
- The only fault caused by the release is GLDS10044's. Not caused by it: exec permission lost on image pages at
  0x4a8330, native CPU only (H10-14:5408-5419, :5567-5578; F3); SIGSYS at libkernel's `sys_exit` return
  (H10-14:2366-2379); `0xa0d0c00a` on switching away (missing `sceGnmSubmitDone`, H10-26:97-101, :127-131).
- **Never measured:** any lowbase-probe output; suspend to rest mode and resume, or Home and back, after the release;
  sessions over tens of minutes; C++ exceptions/unwinding after the release; a first `sceSysmoduleLoadModule` or
  `sceKeyboardOpen` after it; GoldHEN plugins; a Slim, our firmware, our link recipe.

**Our title today** (all of it must move into the title PRX).
- Link: `scripts/ps4/build.sh:466-480` (`build_title`) → `F/tools/build_native_orbis.sh`; sources `:77-82`: title
  `wine64_main_orbis.c, orbislog.c, pw_diagnostics.c, pw_result.c, pw_wine_start.c, pw_wine_prx.c, pw_stage_orbis.c,
  pw_milestone_orbis.c, pw_videoout_orbis.c, pw_pad_orbis.c`; shared `pw_wine_display.c, pw_game_profile.c,
  pw_app_profile.c, pw_script_input.c, pw_vk_stage_orbis.c, pw_cursor_probe_orbis.c, pw_hist.c, pw_wine_launch.c,
  pw_hid_ps5.c, pw_hid.c`. `ld.lld -pie --script link.x` with liborbis-compat.a, libc16, `-lc -lkernel -lc++` and the Sce
  stubs (`:96-100`). Title objects are not built with `-femulated-tls` (`F/tools/orbis-clang:34-37`;
  `build_native_orbis.sh:73-76`).
- Loops: main `wine64_main_orbis.c:722-748` (`alive`, `pw_ms_service` closes VideoOut on the main thread,
  `pw_milestone_orbis.c:2053-2071`); idle `wine64_main_orbis.c:276, :324, :596`; `pw_milestone_orbis.c:1901, :3245`.
- Threads: two fd forwarders (`wine64_main_orbis.c:222`); diagnostics `retry_network`, `write_records`
  (`F/native/pw_diagnostics.c:236-237`); stage watchdog (`pw_milestone_orbis.c:3337`); `g_script` (`:3365-3368`) and the
  d/f/p scripts (`:3370-3373`); `save_readback` (`:1156`), `probe_spin` (`:2560`), `stack_probe` (`:3068`); Wine's main
  thread through the eboot's orbis-compat `pthread_create`, start routine `thread_trampoline`
  (`wine64_main_orbis.c:366-393`) and `run_wine_main` (`F/src/pw_wine_start.c:94-100`), wrapped by orbis-compat's
  trampoline and `runOnItsOwnAltStack` (`refs/orbis-compat/src/orbis_thread.cpp:270-296`).
- Signals: `early_fault` SEGV/BUS/ILL (`wine64_main_orbis.c:327-338`, installed `:638`); `stage_fault` SEGV/BUS/ILL/FPE
  (`pw_milestone_orbis.c:3252-3266`, set `:3336`, SIG_DFL `:3363`). No `sceKernelInstallExceptionHandler` in the fork.
- Devices: VideoOut handle (`:79-80`), opened in `stage_display` (`:698-704`), closed by `release_display`
  (`:2037-2048`); AudioOut port (`:1612`); pad and HID opened inside `g_script` after `pw_ms_wine_begin` (`:4211-4215`),
  racing any release; HID retries `sceSysmoduleLoadModule` and `sceKeyboardOpen`/`sceMouseOpen` every 5 s while a device
  is missing (`:4255`; `F/native/pw_hid_ps5.c:67-110, :251-257`); gc1's cursor probe is eboot code, g's cursor is in
  libvulkan.prx.
- Not done: no `sceSystemServiceLoadExec` call (comments only: `wine64_main_orbis.c:22, :550`;
  `F/wine/orbis/pw_wine_exit_orbis.h:8`); no `sceGnmSubmitDone` (row 1).
- PRX loading: ntdll by `sceKernelLoadStartModule` → module info → descriptor → `module_start(0, NULL)` by hand →
  `pw_wine_dl_adopt` (`pw_wine_start.c:28-63`); stage loads `load()`/`ntdll_ready()` (`pw_milestone_orbis.c:251-257,
  :1940-1974`); the rest through ntdll's dlopen.
- **Pointers into the eboot handed to PRXs (dangle after a release):** `__wine_ps5_set_output_sink(wine_output_sink)`
  (`wine64_main_orbis.c:646` → `:227`); the exit hook (`:647` → `:265`, passed on to wineserver,
  `pw_wine_exit_orbis.h:27-29`); the stage exit hook (`pw_milestone_orbis.c:1967` → `:1891`); `pw_ms_present`
  (`:675` → `:854`); `pw_ms_flush` (`:676` → `:838`); `pw_ms_audio` (`:683` → `:1576`); `pw_ms_release_display`
  (`:685` → `:2053`); `argv` for `__wine_main` from eboot statics `wine_argv`, `exe`, `profile_words`
  (`wine64_main_orbis.c:422-423, :524-525`; `pw_wine_start.c:110-114`); environment values in `env_text`/profile statics
  (`:397-399`).
- Not affected: no PRX imports a symbol from the eboot (imports go to libkernel, Sce libraries and sibling PRXs,
  `F/tools/build_wine_orbis.sh:283-300`); the eboot exports `environ`, `pthread_create`, `open` ... but nothing binds to
  them. libc++abi's `__cxa_get_globals` is in the eboot (a pthread key with an eboot destructor): minor.

**Packaging.** `scripts/ps4/pkg.sh:73-80` (create-fself `--eboot --paid 0x3800000000000011`, right.sprx,
`sce_module/libc.prx` + `libSceFios2.prx`), `:97-110` (SFO CATEGORY gd, SYSTEM_VER 0). The ~4.4 GiB grant for this layout
is inherited from nx-on-orbis (`pkg.sh:4-9`) and measured by our a (`direct_mib`). A stub + PRX keeps the paid flag and
SFO and adds one file under `sce_module/` (`pkg.sh:20-21, :90`); orbis-win shipped ~16 PRXs there (H10-26:2873-2878);
their 702 MiB direct-memory peak (H10-14:8516) proves nothing about the grant. Unmeasured: log
`sceKernelGetDirectMemorySize` in the first stub package. Where the title PRX lives: `/app0/sce_module/` (theirs,
`stub.c:200`: self-contained, every title change is a reinstall) or `/data/ps4-wine/runtime/` (app PRXs load from /data
at mode 777; `runtime.sh:52-57` already ships title-built PRXs, so a title change becomes `runtime.sh --prx-only`; the
cost is skew between the package's stub and a stale PRX, mitigated by /data then /app0 as `runtime_roots`,
`wine64_main_orbis.c:520`, plus a build-id check). Recipe (`CLAUDE.md`; `F/tools/build_wine_orbis.sh:265-300`,
`ld_prx`): `-pie --export-dynamic -e module_start`, link.x, `--no-rosegment`, `-z max-page-size=0x4000`, `-soname
NAME.so`, `create-fself -libname=NAME --paid`, a descriptor from `gen_prx_descriptor.py --orbis`, no constructors (crt1
runs none in an eboot either, FIND:2005-2009), `module_start` called by the stub. The stub must NEED every Sce library
the PRX needs: today Net, SystemService, UserService, VideoOut, Pad, AudioOut, Sysmodule (`llvm-readelf -d`).

**Wine's low address space** (`F/.deps/wine-orbis/source/dlls/ntdll/unix/virtual.c`). `mmap_init` reserves
0x10000-0x68000000, 0x7f000000-0x7fff0000, 0x68000000-0x7f000000 (`:1033-1043`), then the high area and the heap
(`:1050-1083`); `reserve_area` halves around a refusal (`:910-979`); `anon_mmap_tryfixed` uses
`sceKernelReserveVirtualRange(FIXED|NO_OVERWRITE)`, any refusal → EEXIST (`:853-879`), size unrounded (`:865`, row 13;
0x40c000 is a 16 KiB multiple). Patches 0570, 0895, 0601 (i386 images below 4 GiB). `mmap_init` runs inside
`__wine_main` (`loader.c:2158` → `virtual.c:4230`), not in `module_start`. Today the eboot range (plus up to 64 KiB of
halving slack) is outside the reserved areas, so a fixed 0x400000 image hits `map_fixed_area` (`:2621-2651`) → refused
→ c0000018 (orbis-win measured, H10-14:12-14; ours unmeasured); relocatable images move (wow32.exe to ~0x110000,
`HANDOFF-f.md:55-56`). **Wine needs no change** if the release precedes `pw_wine_start_run`
(`wine64_main_orbis.c:711-714`). Optional: an occupant diagnostic like WP/1010; upstream #737 is the same idea in three
files (H10-26:5215-5227), not in `refs/prospero-win` (still at our pin 0e7b6b4). `refs/prospero-win`
`DEVELOPMENT.md:123-126`: the PS5 title sits at 4 GiB, leaving 0x400000 free (claimed). `WINE_PS5_BUILD.md:76`:
upstream's 0130 relocates an image whose base is taken, which cannot help a stripped image (H10-26:5249-5262).

**Licence.**

| Item | Licence | nx-on-orbis / orbis-tls.ld code? |
|---|---|---|
| `reloc-wine-app/app_entry.c`, `stub.c` | no SPDX → LGPL-2.1-or-later by `O/LICENSING.md:3-11` | none; the module-info parse equals prospero-win's own `pw_prx_parse_module_info` (H10-26:5264-5266) |
| `lowbase-probe/*` | no SPDX → LGPL-2.1-or-later | none |
| 0001 patch, S0300 :107-127 and :206-218, 0201 (author "Claude", 0201:2) | patches to LGPL prospero-win (`LICENSING.md:13-17`) | none (S0300 :1038/:1044 mention GPL ps5vk in another hunk) |
| `build-relocatable-wine-ps4.sh` | LGPL | builds through `O/src/toolchain/prospero-clang`, which links `orbis-tls.ld` (`:100-101`), and packages with orbis-compat's `make-pkg.sh` (`:115`): **do not port; use our `ld_prx`** |
| WP/1010 | LGPL (Wine) | none |

`refs/nx-on-orbis` has no eboot release and no module-info parsing (grep). orbis-compat's thread code is MIT
(`orbis_thread.cpp:2`). Our `pkg.sh` cites nx-on-orbis and stays in this GPL repo, out of the fork. Ported pieces carry
`From: plastikman/orbis-win <path> @ 2610706 (LGPL-2.1-or-later)` and a `THIRD_PARTY.md` row.

**Risks and the smallest probe for each.**
1. Lazy Sony reads of eboot data (the process param) after the release: `sceVideoOutOpen` measured; `sceSysmoduleLoadModule`
   checks the SDK version (`pw_hid_ps5.c:227-229`, ESDKVERSION measured) and HID retries it after the release. Probe:
   release, then a second VideoOut open/close, `sceSysmoduleLoadModule(keyboard)`, `sceKeyboardOpen`, `scePadOpen`,
   `sceKernelLoadStartModule(pw_probe_mod)`, pthread create/join, a netlog send; each rc logged.
2. Taking 0x400000 back on our Slim, firmware and recipe: a FIXED|NO_OVERWRITE reserve of 0x400000+0x40c000, then
   `stage_low_map` (`pw_milestone_orbis.c:2168-2206`).
3. Unwinding over a missing eboot (libunwind is linked): throw/catch and `_Unwind_Backtrace` in the PRX after the
   release.
4. TLS: lld relaxes a PRX's TLS to local-exec offsets from the main block (`F/wine/orbis/pw_emutls_orbis.c:4-14`), and
   the stub's PT_TLS must stay compatible; new threads' TLS init image comes from the eboot's PT_TLS. Probe: load
   `pw_probe_tls` and create threads after the release.
5. Suspend/resume, the PS button, LoadExec: close measured, suspend/resume not; the title lacks `sceGnmSubmitDone`.
   Probe: Home and back, later rest mode.
6. Order and races: g_script's pad/HID open and every sink, hook, thread and argv must live in the PRX; the release
   comes after the stage opens (VideoOut first) and before `pw_wine_start_run`.
7. The direct-memory grant with a stub eboot: log `sceKernelGetDirectMemorySize`.
8. GoldHEN plugins: note the plugin list in the probe's LOG line.

**Open.** Which process-param reads are lazy; whether module 0's info still lists the unmapped segments (an
enumeration hazard); whether the stub needs a PT_TLS; /data vs /app0 for the title PRX.

### C. The DS4 as XInput controller 0

**Summary.** The runtime already has the PS5's title-pad path except one PRX. The i386 `xinput1_3.dll` in
`build/runtime/win/wine/lib/wine/i386-windows/` contains patch 0470/0471's code (strings "controllers 0-3 are the
title's", `find_title_pad`), and `ntdll.prx` exports the pad slot. Missing: `xinput1_3.prx`, the Unix library that
code loads by name. Today `XInputGetState` → `__wine_load_unix_lib(L"xinput1_3")` fails (`STATUS_DLL_NOT_FOUND`), falls
back to HID, finds nothing: "not connected". orbis-win hit exactly this: 32-bit GTA IV polled XInput 42188 times and got
`0xc0000135` (`refs/orbis-win/docs/FINDINGS.md:3760-3779`), then built the PRX (`refs/orbis-win/scripts/prx-ps4.sh:97-121,
192-197`) and logged "controller 0 is the title's" (`FINDINGS.md:3778-3797`).

**The PS5 path (code).**
- Switch: profile `[input] mode = xinput` (`F/src/pw_game_profile.c:177-184`); a profile that binds nothing defaults to
  it (`:739-745`); resolved by `pw_wine_library_input` (`F/native/pw_wine_library.c:212-221`), called at
  `F/native/wine64_main.c:1112`. xinput mode also sets `SDL_JOYSTICK_RAWINPUT=0` (`wine64_main.c:1156-1160`).
- Read: `pw_pad_ps5_open` (`F/native/pw_pad_ps5.c:98-118`: foreground user, `scePadInit`, `scePadOpen`, vibration
  compatible mode); `pw_pad_ps5_read` up to 64 samples with `scePadRead` (`:142-180`); intercepted bit `0x80000000` →
  sticks centred (`:9`, `:160-164`); touch half (`:74-96`).
- State: `PwWinePad {connected, packet, buttons, triggers[2], axes[4]}` (`F/wine/ps5/pw_wine_sink.h:71-77`), same layout
  as 0470's `struct xinput_pad_state`.
- Transport: a mutex-protected slot in the sink linked into `ntdll.prx`, not the input queue, not HID.
  `pw_wine_set_pad`/`pw_wine_set_pad_at` number a packet on change (`F/wine/ps5/pw_wine_sink.c:195-208`); reads record
  `pads_wanted` (`:209-221`); rumble per slot with a changed flag (`:223-246`). The title looks them up in ntdll.prx with
  `pw_prx_lookup` in xinput mode only (`wine64_main.c:1297-1317`).
- Wine side: 0470 gives xinput a unixlib; `pad_init` finds the sink by `dlsym(RTLD_DEFAULT, ...)` (0470:287-290; 0471:136
  uses the `_at` forms). `RTLD_DEFAULT` searches every module registered with pw_wine_dl
  (`F/wine/ps5/pw_wine_dl_libc.c:40-55`, `pw_wine_dl.c:170-178`), ntdll.prx included (`F/src/pw_wine_start.c:61-62`).
- PE side: one DLL serves xinput 1.1-1.4 and uap; 9_1_0 forwards to 1.4 (`F/tools/build_wine_ps5.sh:94-102`).
  `find_title_pad` (0470:72-99); GetState(Ex)/GetKeystroke read the slot; `XInputEnable(FALSE)` reads neutral, stays
  connected (0470:102-118); SetState/Enable pass rumble (0470:121-162); GetCapabilities(Ex): wired 360 pad 045e:028e,
  buttons 0xf3ff, force feedback (0470:211-235). 0471: controllers 1-3; a disconnected slot is re-asked once a second
  (0471:65).
- Mapping `pw_wine_game_pad` (`F/native/pw_wine_display.c:400-438`): Cross A, Circle B, Square X, Triangle Y, L1/R1,
  L3/R3, d-pad, Options Start, Create Back (`:400-405`); touchpad click left half Back, right half Guide (`:430`);
  triggers 0-255 raw (`:431-432`); sticks to ±32767, y flipped (`pad_axis`, `:409-414`); no deadzone (the game's own);
  intercepted → connected and neutral (`:420-425`).
- Rumble: 0-65535 → `>>8` → `pw_pad_ps5_vibrate` (`wine64_main.c:1610-1619`) → `scePadSetVibration` + a trigger effect
  (`pw_pad_ps5.c:271-297`); motors stop on close (`wine64_main.c:1729-1731`).
- Coexistence: profile bindings still post key/mouse edges in xinput mode (`wine64_main.c:1597-1609`); USB kbm through
  the queue as before; the in-game menu/OSK make the pad read neutral (`:1497-1534`).
- Only 0470 and 0471 touch `dlls/xinput*`; nothing touches dinput, winebus or hidclass. 0550 (no process creation) is
  why winedevice and the HID stack cannot run. Fork `CONTROLS.md:146-152`: DirectInput games "don't see the DualSense
  yet".

**Orbis today (code).**
- Applied: the Orbis build applies the PS5 series (`F/tools/build_wine_orbis.sh:58-61, 90-91`), so 0470/0471 are in.
  ntdll.prx exports the slot (`:373-374`); the staged ntdll.prx (2026-11-02 03:27) has all seven `pw_wine_*pad*`/
  `*rumble*` names.
- Missing: no xinput in the default module list (`:40`), the Unix-side loop (`:235-236`) or any `link_prx`.
- WoW64 needs no thunk: `MemoryWineLoadUnixLibByName` becomes the Wow64 variant
  (`F/.deps/wine-orbis/source/dlls/wow64/virtual.c:716-723`), ntdll takes `__wine_unix_call_wow64_funcs`
  (`dlls/ntdll/unix/virtual.c:1175-1179, 6930-6950`); the unixlib exports that table (0470:323-330); its structs carry
  no pointers (0470:22). The same mechanism already serves 32-bit Bloodlines' wineps5, ws2_32, winevulkan.
- 32-bit evidence: PS5 Half-Life (32-bit, wowprospero) opens the DualSense through XInput (fork `CONTROLS.md:137-143`,
  `DEBUGGING_GUIDE.md:635`), indirect; orbis-win's 32-bit GTA IV (above) and Fallout 3/NV profiles in xinput mode
  (`refs/orbis-win/src/profiles/*.profile`). No fork test of the PE/Unix xinput path.
- Our pad: `pw_pad_orbis` (`F/native/orbis/pw_pad_orbis.c:21-39`: initial user, `scePadOpen(user,0,0,NULL)`,
  `scePadReadState`); `PwPadOrbisState` names buttons, sticks, triggers, raw `rest[]`, connected at byte 76
  (`pw_pad_orbis.h:19-27`); no vibration or light bar anywhere. Pad loops: d1 (`pw_milestone_orbis.c:569-591`), d/f
  (`:1195-1210`, `:1314`), p (`:1712`, `:1742`), g (`:4211`, `:4284`).
- Plan g's loop `g_script` (`pw_milestone_orbis.c:4192-4360`): ~8 ms poll (`:4358`); touchpad tap marks on release
  (`:4310`); touchpad + square/triangle start segments and never reach the game (`:4292-4311`); the rest through
  `pw_wine_pad_map_step` minus the touchpad bits (`:4321-4328`); reads failing >250 ms release everything (`:4329-4338`);
  connected and intercepted never checked.
- Bindings: `g_bindings` (`:4100-4133`) loads `<root>/input/<preset>.input`, built-in fallback, profile overlay,
  default-mode rule, touchpad forced to NONE. `profiles/input/vtmb.input:41` `mode = keyboard`; `:39` Share is the
  system's.
- Mode selection: the Orbis main never reads `input.mode`; `wine64_main_orbis.c:664-686` hands the plans only
  `pw_wine_post_input`; the profile is loaded for plan g or `PS4WINE_PROFILE` (`:553-569`; `pw_milestone_orbis.c:3197`).

**DS4 vs the PS5 code's assumptions.** `OrbisPadData` (`~/.local/opt/openorbis/include/orbis/_types/pad.h:85-99`) vs
`PwPadPs5Data` (`F/native/pw_pad_ps5.h:17-22`): both 120 bytes (PS4 measured `pad_bytes=120`, `LOG.md:72`); buttons 0,
sticks 4/6, L2/R2 8/9, touch block at 52, timestamp 80, count 104: identical. Connected: PS5 `int32_t` at 76, PS4
`uint8_t` at 76 + 3 padding bytes. Button bits identical (`pad.h:15-36` vs `F/src/pw_game_profile.c:15-21`); DualSense
Create (0x1) has no app-readable DS4 twin (Share is the system's). The PS4 reports the intercepted bit too
(`LOG.md:95`). `OrbisPadVibeParam {lgMotor, smMotor}` (`pad.h:111-114`) matches. The OpenOrbis `libScePad` stub has
Close, GetControllerInformation, Open, Read, ReadState, ResetLightBar, SetLightBar, SetVibration only: no
`scePadSetVibrationMode`, no `scePadSetTriggerEffect`, so `pw_pad_ps5.c` does not link as is (`:24-26`).
`scePadGetControllerInformation` gives the touch resolution (`pad.h:124-135`), unmeasured for the DS4.

**Precedent.** orbis-win compiles `pw_pad_ps5.c` with `-DPW_PAD_PS5_HOST_TEST` plus a 96-line PS4 ops table
(`refs/orbis-win/src/native/pw_pad_ps4.c:1-98`, `FINDINGS.md:667-686`), LGPL-2.1+ (`LICENSING.md`): portable with a
`From:` line. It zeroes the touch data, so a touchpad click always reads as Guide.

**Tests that exist.** `F/tests/test_pw_wine_display.c:172-260` (`pw_wine_game_pad`), `F/tests/test_pw_wine_sink.c:67-80,
312-367` (packets, slots, rumble), `test_pw_pad_ps5`/`test_pw_pad_players` (`F/Makefile:59, 84, 134-135`). No xinput
test. Sample-exe pattern: `F/tests/wine_d3d9tri32.c:161` prints one line, built by `R/scripts/ps4/prefix.sh:34, 62, 72`;
the title captures it by prefix in `pw_ms_stdout` (`pw_milestone_orbis.c:2213-2230`) and embeds it in the plan line
(`:3424-3437`); host check like `F/tests/test_wine_d3d9tri32.py:1-40`.

**Upstream.** `refs/prospero-win` HEAD is our pin 0e7b6b4; none of its other branches' 95 commits touch pad/xinput;
#736 (58b6e0c) is not in the checkout. orbis-win's 0470 is identical to ours.

**Open.** Whether Psychonauts reads the pad through XInput only (DINPUT8 for kbm?); Back/Guide on the DS4 (touchpad
halves cost the marks); the DS4's touch x range; the padding bytes 77-79; whether `scePadSetVibration` moves the DS4's
motors from this title.

### D. Psychonauts under Wine, Proton and DXVK (web, 2026-11-02)

Labels: **[off]** developer/GOG/WineHQ maintainer, **[rep]** a reporter measured or tested it, **[anec]** anecdote,
**[local]** read from the game's own files (small members only). Not loaded: PCGamingWiki and CodeWeavers (403), WineHQ
AppDB (bot wall), parts of Steam (429), the ProtonDB app page (JavaScript; its summary API was used).

**What GOG 2.2.0.13 is [local].** `Psychonauts.exe` FileVersion 1.1.603.0, linked 2016-01-05, imports `XINPUT1_3` and
`steam_api`, carries Transgaming/Cider strings (`pBIsTransgaming`, `TGGetOS`): the Steam-era code base; "2.2.0.13" is
the installer's version. The bundled `ReadMe.txt` is v1.04's (2005-09-21).
- Audio chain: game → `isactwin.dll` (Creative ISACT 1.5, 2011-09-29, needs `vorbisfile.dll`) → `AudioDrv.dll` (ISACT
  renderer on OpenAL: `alcOpenDevice`..., "EAX4.0", "EAX4.0Emulated"; imports `OpenAL32.dll`) → the shipped Creative
  `OPENAL32.dll` 1.09 ("DirectSound3D" device; imports WINMM, ole32; references `eaxac3.dll`) → Wine's dsound/winmm.
  Bink (`binkw32.dll`, RAD 1994-2002) plays through DirectSound directly (`_BinkOpenDirectSound@4`).
- Switches in the EXE: `-width`, `-height`, `-refresh`, `-fullscreen`, `-antialias`, `-nosound`.
- `DisplaySettings.ini`: `ScreenWidth`, `ScreenHeight`, `FullScreen`, `VSync`, `FSAA`, `FSFX`, `AdvancedShading`,
  `Shadows`, `GammaCorrection`. `AudioSettings.ini`: `UseEAX`, `HardwareAccel`, `PacketSize`, volumes,
  `ShowSubtitles`. Other strings: `EnableRumble`, `JoystickDeadzone`, `SmartCamera`, `CameraAltitudeDampening`,
  `InvertCam*`; beside `../psychonauts.ini`: `minfps`, `@maxfps`, `relativegamespeed`, `onetick`, `SyncFrameRate`,
  `TripleBuffering`, `AnisotropicFiltering`, `SoftwareVerts` (effects unknown).
- Saves: `SHGetFolderPathA`, `%s\Profiles`, "Save games have been migrated from their old locations." + `migrated.txt`.
  Double Fine: `%localappdata%\Psychonauts\Profiles\`
  (https://www.doublefine.com/games/support/where-can-i-find-my-psychonauts-saves) **[off]**; PCGamingWiki snippet:
  older builds used `<game>\Profiles`, the two settings INIs live in the same base folder **[rep]**. No registry use
  found.

**Status.**
- ProtonDB 3830: gold, best platinum, trending gold, 89 reports
  (https://www.protondb.com/api/v1/reports/summaries/3830.json, fetched 2026-11-02) **[rep]**. 2018-19 reports
  (https://protondb.max-p.me/games/3830/reports): bindings scrambled after a restart or level load (also native);
  D9VK fixed wined3d's graphics (2019-09-19); 1000 Hz mouse polling hurt frame times; the d-pad did not navigate menus,
  only the sticks (2019-06-12) **[rep]**. Proton 10.0-3 (~63 days old): silent crash after the 2nd cutscene, a 1 s freeze
  in the tutorial, stutter in the late board game (search text of https://www.protondb.com/app/3830) **[rep,
  secondhand]**.
- PCGamingWiki snippet: on Linux some cutscenes crash when movie files are not found by name; fixes: lowercase
  hardlinks or English (https://www.pcgamingwiki.com/wiki/Psychonauts) **[rep, page not loaded]**.
- Proton #6525 (2023-02-12, open, https://github.com/ValveSoftware/Proton/issues/6525): keyboard/mouse prompts only,
  inconsistent pad, garbled bindings every launch; a "one or more important but non-fatal problems" overlay that goes
  away on Proton ≤ 6.3-8; 2025-09-19: native `xinput1_3` fixed the garbled defaults, the pad still undetected **[rep]**.
- WineHQ Bugzilla (https://bugs.winehq.org/buglist.cgi?quicksearch=ALL%20psychonauts): only **20834** open, "Mouse
  buttons need to be reassigned every play", pad bindings return as keyboard keys (to Staging 2.18, 2017-12-17; GOG
  build 2015-07-18). Closed: 9270 (bindings reset, 2008), 20831 (flicker) and 20832 (OpenAL voice crackle) fixed in
  1.3.20 (2011-05-13), 28053 (r600g glitches, abandoned 2015), 12530 (`D3DXFilterTexture`, 2010) **[off/rep]**.
- AppDB: only a 2009 Silver on Wine 1.1.16 through search **[unverified]**.
- DXVK: **no Psychonauts entry** in `src/util/config/config.cpp` at v2.6.2 or master (1635 lines grepped); no DXVK
  issue mentions it.
- Lutris (https://lutris.net/api/installers/psychonauts): plain win32 prefix + virtual desktop, no overrides, no
  winetricks, no DXVK settings; the Linux script writes `language` into `game/Psychonauts.ini` **[off, community]**.
- No source requires native `d3dx9_40` or `msvcr90`.

**Audio.** Patch 1.05 removed EAX/OpenAL hardware sound; `UseEAX=true` re-enables EAX, OpenAL Soft in place of
`OPENAL32.DLL` gives surround (https://www.gog.com/forum/psychonauts/psychopad_xbox_360_controller_gui_unofficial_patch/page1,
https://www.play-old-pc-games.com/2015/02/19/psychonauts/) **[anec/rep]**. Stutter blamed on the bundled OpenAL; a
newer OpenAL or OpenAL Soft helped (https://steamcommunity.com/app/3830/discussions/0/558754899758601237/, 2014)
**[anec]**. The 2012 native Linux port's cutscene FPEs (Bink audio) are that port's
(https://bugzilla.icculus.org/show_bug.cgi?id=5543) **[off, Linux only]**.

**Video and frame rate.**
- **Physics depends on frame rate:** above 120 fps doors open slower, trampolines weaken, pole and ladder dismounts
  fail; PCGamingWiki suggests a 60 fps cap (snippet) **[rep]**; its talk page: problems even at 60, uncapped ~300 fps
  (https://www.pcgamingwiki.com/wiki/Topic:Wea3q3b1jgq2n38w) **[rep]**; Steam: above 60 "breaks physics", in-game VSync
  at 60 Hz caps at 60 (https://steamcommunity.com/app/3830/discussions/0/3040481812837439477/, 2021) **[anec]**.
- Widescreen: non-4:3 stretches the menus; some Bink cutscenes stay 4:3; resolution in `DisplaySettings.ini`
  `[DisplaySettings] ScreenWidth/ScreenHeight` (https://steamcommunity.com/app/3830/discussions/0/412449431007785301)
  **[rep]**; ThirteenAG's widescreen fix needs a DLL override.
- AMD: 2014 Windows drivers after Catalyst 13.12 made foliage flicker
  (https://steamcommunity.com/app/3830/discussions/0/558747287594985726) **[anec]**; missing textures in Gloria's
  theater (2011, https://forums.anandtech.com/threads/psychonauts-major-update-out.2195217/latest) **[anec]**; r600g
  missing models (bug 28053, unconfirmed).
- Readme [local, off]: Pixel Shader 1.x, software vertex fallback; tuning order VSync → resolution → FSAA → Adv.
  Shading → FSFX → Shadows. Patch 1.05 reportedly stuttered more than 1.04
  (https://www.gog.com/forum/psychonauts/any_chance_well_see_the_steam_update_on_gog, 2011) **[anec]**.

**Input.**
- Xbox 360 pad support came with the Steam update of ~2011-09-30 (1.05); GOG lists "Controller support"
  (https://www.gog.com/en/game/psychonauts) **[off/anec]**.
- **Root cause of the garbled bindings** (psycho_fix, 2026-04, https://github.com/jdaniellee/psycho_fix) **[rep]**:
  the game passes gamepad codes through `GetKeyboardLayout` + `MapVirtualKeyEx`, which Wine mangles; the mangled codes
  are written to the bindings ini and the prompts come out wrong. Their fix flips a JZ to JNZ at the pattern
  `85 C0 74 11 8B 4D 08 51 E8`, **present once in our EXE at file offset 0x4F9D** [local] (the byte at 0x4F9F, 74→75).
- PsychoPad X (2026-10-31, for GOG EXE 1.1.500, not our 1.1.603; https://github.com/f4mrfaux/psychonauts-controller-fix)
  **[rep]**: the game polls `XInputGetState(0)` only (**slot 0**), checks for an XInput device **only at startup**
  (else DirectInput), counts any trigger value > 0 as a press, feeds the right stick to `JoyZ`/`JoyRotZ`.
- Camera spin on Proton (triggers read as an axis), "fixed" by another Proton or unbinding the triggers
  (https://steamcommunity.com/app/3830/discussions/0/3735205021139940847/) **[anec]**.
- Needs a mouse or keyboard: the readme says to click binding boxes with the mouse [local]; PCGamingWiki snippet: pad
  "not working in the options menu"; psycho_fix: "you may still need trackpad to navigate the options menu"; bindings
  are repaired with Options → Bindings → Defaults. GOG ships a separate `Language Setup.exe` [local].

**Stability.** No level-specific crash reports for Windows. Random crashes between levels, fixed with XP/95
compatibility mode (https://steamcommunity.com/app/3830/discussions/0/828936719077731733/, 2013) **[anec]**. Double
Fine: compatibility mode XP SP3 (https://www.doublefine.com/games/support/instability-and-crashes-psychonauts); animation
and control glitches when **not installed on C:**
(https://www.doublefine.com/games/support/animations-and-control-issues-psychonauts) **[off]**. Readme [local]: 1.01
fixed a crash on CPUs without SSE, 1.04 a memory bug and overlapped-I/O alignment; `PsychoDump*.dmp` crash files since
1.02. Steam Deck: a crash before Sasha's training (2023-01-24) **[anec]**. No LAA patches, no save corruption, no load
time reports found.

**Performance.** Readme minimum: PIII/Athlon 1.0 GHz, 256 MB, GeForce 3 / Radeon 8500; recommended: P4 2.0 GHz, 512 MB,
GeForce FX 5600 / Radeon 9600, EAX 2.0 [local, off]. GOG today: Win10, 1 GHz, 2 GB. Original Xbox frame rate: not found.
No weak-CPU data.

**Likely problems, ranked:** (1) pad bindings mangled through `MapVirtualKeyEx` (bug 20834, Proton #6525); (2) XInput
detected at startup only, slot 0 only, any trigger > 0 is a press; (3) physics tied to frame rate: cap at 60; (4) the
cutscene crash / movie names; (5) Creative OpenAL 1.09 → ISACT over our dsound driver; (6) no 16:9 HUD, 4:3 Bink; (7)
AMD foliage/texture reports; (8) the options menu not fully pad-navigable, `Language Setup.exe`.

**Unknowns.** Xbox prompt icons in 1.1.603; whether our Wine's `MapVirtualKeyEx` mangles codes ≥ 0x100; what
`maxfps`/`minfps`/`relativegamespeed` do; the full PCGamingWiki and AppDB text; the Xbox frame rate; Jaguar performance;
memory use against the 2 GB limit; the "not on C:" bug under a Wine drive mapping; DirectSound3D on our driver.

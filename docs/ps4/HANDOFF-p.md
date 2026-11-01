# Hand-off: phase p (performance and audio, before milestone g)

Written 2026-11-01, after milestone f passed (repo `13ddea7`, fork `73a9a10`). Read `CLAUDE.md`,
then this, then `MILESTONES.md` (the p note and table, the g row and note), `HANDOFF-f.md` (plan
`f`, "Games on the host", the native readiness notes that became p2) and the last lines of `LOG.md`.

## Resume here (2026-11-01 18:40: p1, p3, p4 done; p2 next)

**p3 passed on `vo720`** (LOG.md 18:31) and **p4 passed** (18:40), both checked over HDMI on the
recording of the launch. Five launches of the p3/p4 package in all (LOG.md 18:21-18:40):

| Launch | Path | Result |
|---|---|---|
| 18:21 p3 | vo540: 960x540 A8R8G8B8 | FAIL: `sceVideoOutRegisterBuffers` 0x80290005 at pitch 960 and 1024. VideoOut refuses 960x540 (as it refused 2160p in a); the display never opened |
| 18:28 p3 | vo720 | FAIL, not a measurement: the 18:21 launch's progress file (closed before its last stage ended) was resumed |
| 18:31 p3 | vo720: 1280x720 A8R8G8B8, 1280x720 desktop, one row copy | **PASS**: VideoOut scales the 720p buffer to the 1080p output (pattern at 1.5x on HDMI); copy 0.92 ms (p1: 12.94, T3: 11.65) |
| 18:36 p3 | vo1080: 1920x1080 A8R8G8B8, CPU 2x by rows | FAIL: copy 111.9 ms: each row was copied to the next one by reading it back out of the write-combined scan-out buffer. A fault of the code (fixed in the source since, not re-run), not of 1080p buffers; the format shows correctly |
| 18:40 p4 | vo720, 3 buffers, async flip | **PASS**: 59.9 flips shown/s for 59.9 presents/s, no flip error; but every present waited for a free buffer |

What p3 and p4 say:
- **The copy is gone as a cost:** 0.92 ms instead of 12.94 ms per present, by letting VideoOut scale a
  1280x720 buffer. The desktop for this path is 1280x720 (`WINE_PS5_DESKTOP`); Pinball's window is
  the same size, with more black around it.
- **The time saved went to the vblank wait** (flip 15.5 ms in sync). In attract mode Pinball presents
  again ~0.2 ms after a present returns, so it is held by the display at 59.9/s whatever the present
  path: sync waits in `IsFlipPending`, async in the slot wait (`slot_waits` = every present). As the
  review predicted: p4's gain (no missed vblanks, a present that returns early) shows only when the
  guest itself needs most of a frame. Attract mode does not.
- **Formats:** A8R8G8B8_SRGB shows the driver's B,G,R,X (alpha 0) correctly at 1280x720 and 1920x1080.
- **For g:** none of this touches DXVK's path (`wsi_orbis.c`). For GDI games, `vo720` with async is
  the faster sink; neither is the title's default yet (plan f still uses the scale path).

**Changed since the plan (2026-11-01):**
- `vo540` is replaced by `vo720` (1280x720 buffers, 1280x720 desktop, VideoOut scales) and `vo1080`
  (1920x1080 buffers, no swizzle, CPU 2x). The user chose to test both.
- The p3/p4 lines are `PS4WINE p3|p4 bench pinball ...` with `present_path=`, `present_mode=`,
  `buffers=`, `shown_hz=`, ... fields; the rules read the fields (`check.sh p3`: `present_path` in
  vo720,vo1080, `vo_register=ok`, `vo_flip=ok`, `copy_us_avg<=11647`; `check.sh p4`:
  `present_mode=async`, `buffers=3`, `shown_hz>=59`, `flip_errors=0`; both the HDMI pattern, given as
  `--shot` from the recording).
- The pattern follows the desktop: 960x540 (scale, vo1080) or 1280x720 (vo720), green on the centre,
  orange on (w/8, h/8), so full-screen it lands on 960,540 and 240,135.
- After a launch closed before its last stage, the next launch resumes that cycle (18:28): move
  `/data/ps4-wine/<plan>/progress.txt` aside first, or let the resumed launch close the cycle.

**Fixed in the source after the runs (not yet on the console):** `vo1080` widens each row in cached
memory and writes it twice; the guest CPU read happens before the async slot wait (the p4 line's
`guest_cpu_us_avg=465` counted the wait's polling; guest wall time was 0.22 ms).

**Next:** the user commits; then p2 (native WoW64): first the `sigaltstack`-via-syscall-53 stage.

## Earlier: p1 done (2026-11-01 18:06)

**p1 passed**: three passing launches of one package (LOG.md 18:00, 18:03, 18:06,
`ps4-wine-73a9a10+dirty-p1b.pkg`, plan `p1` the title's default, env.txt empty). A first launch at 17:55
measured the same but FAILed its check: the line lost everything past 512 bytes (below).

Pinball's attract mode, per present, the three launches' averages (p95 in brackets):

| Metric | 18:00 | 18:03 | 18:06 | Spread s |
|---|---|---|---|---|
| copy (swizzle + scale) | 12940 µs (13100) | 12945 (13100) | 12939 (13100) | 0.05 % |
| flip wait | 2813 (4100) | 2481 (4000) | 2813 (4100) | 12.3 % (p95: 2.5 %) |
| keep (`last_drawn`) | 690 (900) | 1034 (1200) | 690 (900) | 42.7 % |
| guest | 218 (400) | 211 (400) | 217 (400) | 3.3 % |
| guest CPU | 225 | 218 | 225 | 3.1 % |
| frame (entry to entry) | 16682 | 16691 | 16682 | 0.05 % |
| present (entry to exit) | 16463 | 16479 | 16464 | 0.1 % |
| presents in 60 s | 3597 | 3595 | 3597 | 0.06 % (0.033 Hz) |

What p1 says:
- **The copy is the cost.** 12.9 ms of the 16.5 ms present is the swizzle and the 2× scale, every
  present. The flip wait is what remains of the vblank (2.5-2.8 ms); keep adds 0.7-1.0 ms; the guest
  needs 0.2 ms. The plan's guess (the copy is the largest cost besides the flip wait) is confirmed:
  it is the largest cost outright.
- **59.9 presents/s, every one a surface flush** (`noted` = `flushes` = `presents`), none full-screen,
  none composed (no pointer drawn). Attract mode changes 850-1200 px per flush on average (max 99824
  of 518400), and each costs a full 1920x1080 copy. Still unmeasured: how many flushes make one
  Pinball frame. Every present blocks for a vblank, so 59.9/s is the display's rate, not Pinball's;
  two flushes per game frame would look the same.
- **Guest CPU equals guest wall time** (0.22 ms both): the guest does not wait between presents.
  `getrusage(RUSAGE_THREAD)` from libkernel works; `thread_cpu_other=0` (one presenting thread).
- **keep is bimodal across launches** (0.69 or 1.03 ms, the same within a launch); cause not measured
  (where `last_drawn` lands, cache state). It is not gated.
- **One missed vblank** in 3595 presents at 18:03 (a 17.6 ms flip).
- **fps 54 in f vs 59.9 here:** f's 54 was hand play, these are attract mode; not compared (by design).

**Built for p1 (uncommitted; the user commits):**
- Fork:
  - `native/orbis/pw_hist.{c,h}` (new, title code: the core `src/` formats nothing,
    `tests/test_native_contract.py`) and `tests/test_pw_hist.c`, in the Makefile and
    `build_native_orbis.sh`;
  - `native/orbis/pw_milestone_orbis.{c,h}`: plan `p1`, `p_script`, the per-present timings in
    `pw_ms_present`, `pw_ms_flush`, `p1_lines`; f's play loop split into `f_play` (p1 runs it after
    the line);
  - `native/orbis/wine64_main_orbis.c`: the flush sink set from ntdll's descriptor; the netlog
    datagram buffer 2100 bytes;
  - `native/orbis/orbislog/orbislog.c`: datagrams up to 2048 bytes, klog stays 512
    (`ORBISLOG_KLOG_MAX`);
  - `wine/ps5/pw_wine_sink.{c,h}`: `pw_wine_set_flush_sink`, `pw_wine_note_flush` (tested in
    `tests/test_pw_wine_sink.c`), exported by `ntdll.prx` (`build_wine_orbis.sh`);
  - `wine/patches/1080-win32u-orbis-note-each-present.patch`: `present_screen` tells ntdll each
    present's dirty area, the desktop's area and whether it composed. Numbered 1080, after every
    patch that touches `ps5drv.c` (the last is 0902): as 0490 it did not apply to a fresh series.
- Repo: `check.sh p1` (with `num`; the line is the last copy or a longer copy it begins, because
  klog keeps 512 bytes), `tests/check_p1_test.sh` + 8 fixtures, `build.sh probe-test` runs it.
- Host tests: fork `make test` exit 0; `build.sh probe-test` exit 0 (a-f, p1).

**Measurement notes for later steps:**
- "First present" is the first frame after the Wine stage begins: 1.3-1.5 s in, while PINBALL.EXE
  opens its window (it loads at 1.2 s). The segment runs from ~22 s to ~82 s.
- orbis-compat's `clock_gettime` answers every CPU-time clock id with the monotonic clock, so
  `CLOCK_THREAD_CPUTIME_ID` would have been wall time; hence `getrusage`.
- Until 2026-11-01 18:00 every netlog datagram was cut at 512 bytes (`ps5log_raw`), the f lines
  included.

**Next:**
1. The user commits, fork and repo.
2. p2 (native WoW64): first the `sigaltstack`-via-syscall-53 stage. Or p3/p4 (one package, env.txt
   toggles): T3 is written below, before p3's first run.

Phase p does not gate g unless a rule says so. The one link: g runs on the native CPU when p2
passes, else on the translator.

## Known (from the code and LOG.md; stated, not re-derived)

**The present path today** (fork `native/orbis/`):
- `pw_ms_present` (`pw_milestone_orbis.c:680`) swizzles BGRA→RGBA per pixel and integer-scales
  960x540 to 1920x1080 on the CPU, under `present_lock`.
- On every present that draws, it also copies the whole source frame into `last_drawn`
  (`pw_milestone_orbis.c:742-745`, 2 MB at 960x540), kept for the framebuffer readback.
- `pw_videoout_orbis_flip` (`pw_videoout_orbis.c:81`) submits `FLIP_VSYNC` and busy-waits on
  `sceVideoOutIsFlipPending` (up to 100 × 1 ms `nanosleep`) inside that lock. Presents are already
  vsync-locked and block the caller: `present_ms=16.6` in the f line. Two buffers.

**What the f line says about time** (LOG 2026-11-01 16:52):
- 3862 presents in 71 s = 54.4/s, an 18.4 ms frame, 16.6 ms of it inside the present. The guest
  gets ~1.8 ms per frame. The translator is not Pinball's bottleneck.
- A speed gate on guest time would test ~0.2 ms against run-to-run noise. Guest time is recorded in
  every p line and gated nowhere.
- fps (54) sits under a 60 Hz ceiling, and the GDI driver presents only on change. fps is not a CPU
  metric; p compares per-flush times, never fps.
- A "present" is a win32u surface flush, not a game frame. If Pinball's table and score panel flush
  separately, one game frame costs two copies and two vblank waits, which could explain part of the
  54/s. Unmeasured: p1 records it.
- Unblocked, Pinball can exceed 60 frames/s: on the host it ran ~63 fps in attract mode (2517
  frames in 40 s, `HANDOFF-f.md` "Host evidence"). On the Jaguar this is unmeasured; p4's gate
  relies on it.

**The Vulkan path is different** (scope of p3/p4):
- p3 and p4 change the GDI sink only. D3D9 in g presents through mesa-ps4's `wsi_orbis.c`, which
  already returns after `sceVideoOutSubmitFlip` and throttles on a flip slot
  (`wsi_orbis_wait_for_flip_slot`: proceed while `numFlipPending < count-1`, `sceKernelUsleep(500)`,
  2 s bound).
- Measured by mesa-ps4, not by us: the display accepts several pending flips, 21 in ~110 ms, and then
  the queue overflowed and presentation failed (`refs/mesa-ps4/src/vulkan/wsi/wsi_orbis.c:398`,
  `:549`). An async present needs the slot limit.
- The same file says "nanosleep does not return on this platform". Our flip loop's `nanosleep` did
  return in f. The two disagree, so new waits use `sceKernelUsleep`.

**VideoOut sizes** (milestone a, `probes/probe.c:705-718`): a 1280x720 A8R8G8B8_SRGB set registered
(`vo_720p=ok`), a 3840x2160 set was refused (`0x80290005`). Registering a smaller set is measured;
flipping one is not.

## The benchmark (every p launch)

- **Plan `pN`** (`PS4WINE_MILESTONE=pN` in env.txt) is plan `f`'s Pinball with the pad bindings off.
- **Segment:** warm-up W = 20 s from Pinball's first present, then N = 60 s in attract mode with no
  input. The same W and N every run, so runs compare like with like.
- **No input:** the title counts every pad event inside the segment; `inputs=0` is required, so a
  touched pad fails the run instead of skewing it.
- **After the segment** the line is sent. The pad bindings then switch on, and the user may play.
  Hand play goes to a `PW_MS play` record and the LOG notes, never into a comparison.
- **Run conditions**, noted in each LOG line: viewer open, no other app running, desktop 960x540.

## p1's instrumentation (stays in every later build)

Each step is re-measured on the same segment with the same fields.

Per present (= per flush), in integer µs (a precision choice):

| Metric | From | To |
|---|---|---|
| `guest` | the previous present's exit | this present's entry (translated code + Wine + the guest's own waits) |
| `copy` | swizzle + scale start (p3: its copy) | end |
| `keep` | the `last_drawn` copy's start | end (its own field, not inside `copy`) |
| `flip` | flip call entry | return (the time the caller spends there) |
| `frame` | present entry | next present entry |

- Fixed 100 µs buckets up to 100 ms plus an overflow bucket, no allocation per frame. Exact
  min/avg/max; p95 from the buckets.
- Line fields: `guest_us_min guest_us_avg guest_us_p95 guest_us_max`, the same four for `copy_us`,
  `keep_us` and `flip_us`, plus `frame_us_avg` and `presents`.
- `guest_cpu_us_avg` from `clock_gettime(CLOCK_THREAD_CPUTIME_ID)` on the presenting thread,
  `thread_cpu=ok|err:<rc>` (unmeasured on Orbis). It separates the guest's CPU time from its waits.
- **Flushes:** `flush_hz` (presents per second over the segment), the dirty area per flush
  (`dirty_px_avg`, `dirty_px_max`) and `full_flushes`. `pw_ms_present` receives the whole frame and
  no rectangle, so the driver tells ntdll each present's dirty area just before it (patch 1080,
  `pw_wine_note_flush` → the title's `pw_ms_flush`). With the histograms this shows
  whether one game frame is several flushes.
- The sparse histograms go to netlog as `PW_MS hist <metric> ...` records for plots, not into the
  line.

## Sub-steps

Each step: its own `PS4WINE pN` line, a `check.sh pN` rule and `tests/check_pN_test.sh` with
`tests/fixtures/pN-*.log` before its first run, one LOG line per launch. Every line also carries
p1's fields, `build=`, `session_s` and the stage fields as in f.

| Step | What | Rule (`check.sh pN`) |
|---|---|---|
| p1 | Measure. 3 launches of one package, for the run-to-run spread | `PS4WINE p1 bench pinball cpu=translator seg_s=60 inputs=0 presents>=600 faults_unresolved=0`, every histogram field present. No performance threshold |
| p2 | Native WoW64 | `PS4WINE p2 native native_caps=7 cpu=native seg_s=60 inputs=0 faults_unresolved=0 segment=done` |
| p3 | Drop the CPU copy (**passed 18:31, vo720**) | `PS4WINE p3 bench pinball ... present_path=vo720\|vo1080 vo_register=ok vo_flip=ok seg_s=60 inputs=0 faults_unresolved=0 copy_us_avg<=T3` **and** HDMI 960,540 = 0,255,0, 240,135 = 255,128,0 |
| p4 | Non-blocking present (**passed 18:40**) | `PS4WINE p4 bench pinball ... present_mode=async buffers=3 seg_s=60 inputs=0 faults_unresolved=0 shown_hz>=59 flip_errors=0` **and** p3's HDMI pattern check |
| p5 | Orbis audio | `PS4WINE p5 audio driver=orbis open=ok seg_s=60 inputs=0 faults_unresolved=0 grains_nonzero>=G underruns=0`, the rate gate below, **and** the recording's audio peak >= D dBFS in the tail's window |

### p1: measure

- The instrumentation above, nothing else changed. The p1 line records numbers only.
- Three launches of the same package give the spread s of each metric (below), which the thresholds
  are built on.

### p2: native WoW64

- f4's readiness probe: an Orbis variant of 0883 as its own patch, not 0883/0903 widened wholesale.
- **First stage, before anything else:** does `sigaltstack` work as syscall 53 through libkernel's
  `syscall` stub? (`sigaltstack` returns -1 through libc, c and d.) Field `altstack53=ok|err:<rc>`.
- The stub is found by checking its bytes (`mov $N,%rax; mov %rcx,%r10; syscall; jb; ret`), as 0883
  does (fork `docs/native-wow64-provider.md`), not used as a fixed `getppid+10` offset (that is
  only where a measured it).
- Then 0883's checks: raw `sigaction` (416) through the stub, the frame check with a marked MXCSR,
  the aligned alternate stack. Caps 0 on any mismatch; the translator runs either way (0614).
- With `native_caps=7`, the segment runs on `cpu=native`.
- **Gate: correctness only** (`native_caps=7`, `faults_unresolved=0`, `segment=done`). `guest_us_*`
  and `guest_cpu_us_avg` are recorded against p1, not gated: with ~1.8 ms of guest time per frame,
  noise would decide any speed gate.
- caps < 7 is a FAIL that names the failing check. g and h then stay on the translator.

### p3: drop the CPU copy

- **Outcome (2026-11-01):** 960x540 is refused by VideoOut; `vo720` passed, `vo1080` failed on a
  read-back fault (see "Resume here"). The text below is the plan as written.
- **First try** 960x540 A8R8G8B8_SRGB linear VideoOut buffers. The driver's BGRA is that format's
  memory order, so a row `memcpy` replaces the swizzle and the scale.
- Whether VideoOut scales a smaller buffer to 1080p is unmeasured (see "VideoOut sizes").
- **The pitch is a parameter:** 960, with 1024 as the fallback if 960 is refused (then the copy is
  row by row).
- **The keep copy:** p3 states whether vo540 keeps the `last_drawn` copy (`keep_us`) or moves it,
  for example by taking the readback from the 960x540 scan-out buffer itself.
- **Test pattern, same launch, before Wine:** the title flips a 960x540 version of d1's pattern for
  3 s, recorded over HDMI. The green centre is at 480,270 and a 32x32 orange square is centred on
  120,67, so a 2× scale puts them on HDMI 960,540 and 240,135. A buffer shown unscaled in the
  top-left corner fails the check, as it should. Fields `vo_register`, `vo_flip`, then the segment.
- **GPU (RADV) only if VideoOut cannot scale.** It loads a 1 GiB arena into a plan that is RADV-free
  today, so that path gets its own decision, not a p3 retry.

### p4: non-blocking present

- 3 buffers. Submit `FLIP_VSYNC` and return.
- Wait only for a flip slot, when `numFlipPending >= count-1`: the WSI's rule. The wait happens
  outside `present_lock`, with `sceKernelUsleep` and a 2 s bound.
- **Path:** p3's result, vo540 if p3 passed, else today's scale path, fixed before p4's run.
- **Gate:** `shown_hz>=59` (flips completed per second over the segment, from the flip status) and
  `flip_errors=0`. The visible problem today is missed vblanks: 54/s, not 60.
- `flip_us_*` and `slot_waits` are recorded, not gated. Once the present returns before vblank,
  Pinball can outrun 60/s and the caller waits for a slot instead, and that wait lands in `flip_us`.
- Same HDMI pattern check as p3.

### p5: Orbis audio on sceAudioOut

1. **Explain milestone a's `sceAudioOutOpen` = 0x809b0001 first.**
   - The probe (`probes/probe.c:727`) called `sceAudioOutOpen(initial user 481013703, MAIN, 0, 256,
     48000, S16 stereo)` (`logs/20261030-001125-a.log`). Its klog at line 602 has
     `[AudioOut] Error:sceMbusAddHandleByUserId 0x20000007`: the system side refusing that user id.
   - OpenOrbis's sample (`refs/OpenOrbis-PS4-Toolchain/samples/audio-wav/audio-wav/main.cpp:24,38`)
     and nx-on-orbis's eden patch 0002 (`UserIdSystem = 0xFF`, the sequence ARCHITECTURE §4.11
     calls clean) open with the SYSTEM user 0xFF.
   - orbis-porting-kit `services/audio/orbis_audio.h:31,115` records 0x809b0001 for a real user id
     instead of SYSTEM.
   - Hypothesis: the user id. The p5 launch's first stage opens with 0xFF (`open=ok user=system`);
     the initial user is tried again only if 0xFF fails.
2. **Facts from `orbis_audio.h`** (facts, no code taken):
   - 48000 Hz only; the grain is a multiple of 256, from 256 to 2048;
   - `sceAudioOutOutput` blocks and is the clock: it runs on its own thread, never a render thread;
   - `sceAudioOutSetVolume` after Open (the port can open silent);
   - open once and never close (close and reopen is disputed: PORT_FULL after eight cycles);
   - one audio output stream per process (`orbis_audio.h:35`): `wineorbis` mixes every Wine stream
     into the one port it opens once.
3. **The title's `native/orbis/pw_audio_orbis.c`**, from `native/pw_audio_ps5.c` with the same
   256-frame grain contract. Counters `grains`, `grains_nonzero` and `underruns` (a grain sent as
   silence while a stream is open and the ring is empty), counted from the first grain to the line.
4. **`wine/wineps5` ported and renamed `wineorbis`** (ARCHITECTURE §4.11), built by
   `build_wine_orbis.sh`. Patch 0120's default driver is `orbis` on Orbis (today mmdevapi logs "No
   driver from ps5 could be initialized").
5. **Host first:** the fork's driver fixture plays Pinball's scripted tail into a host sink (WAV)
   and counts nonzero grains. That count sets G.
6. **The launch:** the segment as in p1, then a scripted tail of title-injected keys (F2 new game,
   space held 1 s and released, Z and `/` flippers) so Pinball plays its WAV effects.
7. **HDMI audio:** `view.sh --record X.mkv` records video only (mpv runs `--no-audio`; the sound
   goes through `pw-loopback`). Add an `X.wav` sidecar recorded from the stick's PipeWire source
   (`pw-record`: a second reader of the audio source, not of the V4L2 node). `check.sh p5` reads its
   peak with ffmpeg `volumedetect`. HDMI audio does reach the laptop: the user heard the home screen
   (LOG 2026-11-01 16:44).
8. **One package, two launches:** `PS4WINE_AUDIO=off|on` in env.txt. The off launch is the baseline
   for the rate gate, on the same present path.
9. **Gate:** `open=ok`, `grains_nonzero>=G`, `underruns=0`, the rate gate (thresholds), the HDMI
   peak. Guest time is recorded, not gated: WaveMix mixes in translated guest code, so audio may
   cost more than ~0.2 ms and still play fine.
10. **MIDI music:** `midi=untested`. It needs a synth that Orbis Wine lacks.

## Thresholds

Written here before each step's first run, from measured numbers, and never moved after seeing that
step's data. Spread s = (max − min) / mean of a metric over p1's 3 launches.

| Step | Threshold | Rule | Value |
|---|---|---|---|
| p2 | none | correctness only | – |
| p3 | T3 for `copy_us_avg` | p1's copy avg × (1 − max(0.10, 3s)). The copy is expected to be the largest cost in the present besides the flip wait; p1 confirms or refutes that before T3 is written. p1 (2026-11-01): mean 12941 µs, s = 0.05 %, so the 10 % floor applies; confirmed, the copy is the largest cost | **11647 µs** (written 2026-11-01 18:06, before any p3 run) |
| p4 | `shown_hz` | >= 59, fixed now from the 60 Hz display (a: 60.5 Hz, d1: 59.9 Hz), not from data | 59 |
| p5 | rate gate | p4 passed: `shown_hz>=59`. p4 failed: `flush_hz` >= the audio-off launch's `flush_hz` − 3 × p1's `flush_hz` spread (in Hz; p1 runs sync and has no `shown_hz`). The branch is fixed when p4's verdict is in. p1's `flush_hz` spread: 0.033 Hz, so 3× = 0.10 Hz | branch after p4; margin 0.10 Hz |
| p5 | G for `grains_nonzero` | the host run of the same tail | after the host run |
| p5 | D (dBFS) for the HDMI peak | above the level of a recording with the PS4 silent | after that recording |

## Batching

- **p1:** one package, 3 launches.
- **p3 and p4:** one package with env.txt toggles: `PS4WINE_MILESTONE=p3|p4`,
  `PS4WINE_PRESENT_PATH=scale|vo540`, `PS4WINE_PRESENT_MODE=sync|async`. Several variants per
  install, each launch its own LOG line. A p1 re-measure (scale + sync) can run from the same
  package.
- **p2:** its own package (patch work).
- **p5:** one package, `PS4WINE_AUDIO=off|on`, two launches, two lines.

## Host first, tests

- `tests/check_pN_test.sh` with `tests/fixtures/pN-*.log` per step: a pass, input during the
  segment, a missing histogram field, a threshold miss, stage records only (NOLOG naming the
  stages).
- p3/p4: HDMI pixels from generated 1920x1080 dumps, as `check_f_test.sh` makes them (scaled
  pattern passes, unscaled top-left pattern and swapped red/blue fail).
- p5: generated WAVs (a sine passes, silence fails).
- `build.sh probe-test` runs them; `check.sh`'s STAGES branch includes `p[1-5]`.
- The histogram and percentile code is host-tested in the fork.

## Not tested / unmeasured (say so in the LOG lines)

- VideoOut scaling a 960x540 buffer, and flipping any non-1080p set;
- A8R8G8B8's colour order on HDMI;
- a 960-pixel pitch;
- `CLOCK_THREAD_CPUTIME_ID` on Orbis;
- syscall 53 (`sigaltstack`) through libkernel's stub;
- attract mode's run-to-run stability (p1 measures it);
- how many flushes one Pinball frame takes, and their dirty area (p1 records it);
- whether Pinball outruns 60/s on the Jaguar once the present is async;
- MIDI.

## Milestone g after p

- The rewritten g (MILESTONES): Bloodlines from `games/bloodlines-up`, `Vampire.exe -game
  Unofficial_Patch`, rule `PS4WINE g vtmb batch=1 crossings_per_frame<=2000 fps_avg>=20
  session_s>=300 faults_unresolved=0`; "gameplay reached, batching on, 300 s".
- Its unmeasured risks, moved from h: VirtualAlloc at fixed addresses, the large-address (2 GB RAM)
  fix, `Vampire.exe` relocated off the eboot's 0x400000.
- What g takes from p:
  - p2 decides the CPU: native when p2's correctness fields pass (`native_caps=7`,
    `faults_unresolved=0`, segment done); speed plays no part.
  - p5 gives sound (Miles goes through Wine's audio); g's rule does not gate it.
  - p3/p4 are GDI-sink only; g's D3D9 presents through `wsi_orbis.c`.

## Iteration loop (as in f)

```
scripts/ps4/build.sh wine --skip-host        # Orbis PRXs
scripts/ps4/runtime.sh --prx-only            # PRXs + *.bind.txt to /data
scripts/ps4/build.sh title                   # when native/orbis changed
cp dist/ps4-wine-<id>.pkg dist/ps4-wine-<id>-<tag>.pkg && scripts/ps4/deploy.sh dist/ps4-wine-<id>-<tag>.pkg
scripts/ps4/logs.sh --label pN --expect 'PS4WINE pN ' --timeout 600 &    # before the user launches
scripts/ps4/view.sh --sink ... --record logs/<ts>-pN.mkv &               # the user's screen + HDMI evidence
scripts/ps4/check.sh pN                      # plus the HDMI checks for p3/p4/p5
```

Choose the plan and variants in `/data/ps4-wine/env.txt` (`PS4WINE_MILESTONE=pN`, the toggles
above). Give each package build its own file name. Close the running title before a reinstall
(CE-33237-8).

# Console run log

One line per launch on the PS4, appended by hand from the output of
`scripts/ps4/check.sh <letter>` (or by hand when no check applies). Raw logs
and screenshots live under `logs/` (gitignored) and are named in the line.

## Line format

```
YYYY-MM-DD HH:MM | <a-h> | build <sha7>[+dirty] | PASS|PASS (framebuffer)|PASS (no shot)|FAIL|CRASH|NOLOG | <check line or first failure> | <notes; logs/<ts>-<label>.log; logs/<ts>-<label>.png>
```

- `build`: the short commit of the tree that produced the package (`scripts/ps4/common.sh` `build_id`), `+dirty` when uncommitted changes were in it.
- `PASS` / `FAIL`: the milestone check's verdict on the captured `PS4WINE` line.
- `PASS (framebuffer)`: the log fields passed and the pixel rules passed on the title's own readback of its presented swapchain image (`check.sh --fb`, fetched over FTP by `fbshot.sh`). This checks the framebuffer, not the HDMI output; the capture-stick pixel rule is still owed.
- `PASS (no shot)`: the log fields passed but the milestone's pixel check (b, e) was skipped with `check.sh --no-shot`; the pixel rule is still owed.
- `CRASH`: the title ended with a kernel fault or CE-34878-0 before its check line (quote the `fault` record or the klog exception line).
- `NOLOG`: no `PS4WINE` line arrived within the timeout (say whether klog, netlog or both were silent).
- Fifth column: the exact `PS4WINE ...` line, or the first failing field, or the first error line.
- Sixth column: what changed since the previous run, what was and was not tested, file names of the raw log and screenshot.

Example (not a real run):

```
2026-11-02 21:14 | a | build 3f2a9c1 | PASS | PS4WINE a hello ok build=3f2a9c1 direct_mib=4464 flex_mib=384 reserve_gib=16 jit=ok | first boot of the samples layout; sysarch not probed yet; logs/20261102-2114-a.log
```

## Known issues

Open problems seen on the console that are not one launch's verdict. Each names the runs it was
seen in; the run lines themselves stay as they were.

- **CE-34878-0 when the triangle is closed from the PS menu** (milestone b, title `PSWN00002`).
  Seen twice, once per build: after the 2026-10-30 00:59 run (`209acfd+dirty`) and after the
  01:11 run (`01c7626+dirty`), reported by the user. The title idles in its present loop and
  never handles the system's close request, so the system tears it down with RADV's arena,
  the swapchain and the VideoOut registration still live. The only close captured in a log
  is the first build's, at the head of `20261030-011110-b.log`:
  `Game Close detected`, then `gbase_gvmsw_close free_vm_space error:-2142502907 (0x804c0005)
  vmid:1`, then `[AppMgr] checkAppTerminated invalid app.` The milestone a probe closes from the PS
  menu without a report (user, 2026-10-30), and it is torn down in the same state minus the GPU:
  idling, close request unhandled, VideoOut port open with CPU-written buffers registered
  (`probes/probe.c` never closes it). So neither an open VideoOut nor an unhandled close is enough
  on its own. What only the triangle has is the GPU side: Gnm submissions, RADV's 1024 MiB arena,
  the GPU VM (`vmid:1`) and flips still queued. The failed `free_vm_space` points there, but that
  is not verified. Not tested: whether releasing Vulkan (device, arena) before leaving avoids the
  report, or whether flips still pending at teardown matter.
  Does not affect the b verdicts (the result line is emitted at frame 300, long before a close),
  and is **not a blocker for c**. Fix tracked as a polish item in `MILESTONES.md`.

## Runs

2026-10-30 00:06 | a | build 97fcc7c+dirty | PASS | PS4WINE a hello ok build=97fcc7c+dirty direct_mib=4464 flex_mib=437 reserve_gib=16 jit=ok sysarch=fs+gs frame_mc=64 frame_fx=320 frame_fs=1152 cs32=ok loadexec=noargs dlsym=ok cpus=4 | first launch, all 11 stages ran, no crash; screen reported by user: amber, brief green, steady green after the LoadExec restart; no capture stick (shot not taken); netlog and klog both received; loadexec=noargs is a probe bug: the restart got argv[0]=--ps4wine-loadexec (argc=1), the probe scanned from argv[1], so LoadExec with arguments works; cpus=4 is a test artefact: cpu_mask=0x3f and sysconf=6, threads 6/7 were refused affinity (0x80020001) and shared cores 1/4; frame offsets equal prospero-win's PS5 values (mc 64, FXSAVE 320, FS base 1152, cs 0x43, both sigaction and sceKernelInstallExceptionHandler); far jump to 0x33 and back ran 32-bit code; rdfsbase SIGILL; getppid stub has syscall at +10; modstart=0 (PRX constructor did not run) with dlsym ok; audio open 0x809b0001; 2160p buffers refused 0x80290005, 720p ok; flip 60.7 Hz; not tested: shot pixel, audio output, VideoOut sizes beyond the two; 20261030-000148-a.log
2026-10-30 00:13 | a | build 39831da | PASS | PS4WINE a hello ok build=39831da direct_mib=4464 flex_mib=437 reserve_gib=16 jit=ok sysarch=fs+gs frame_mc=64 frame_fx=320 frame_fs=1152 cs32=ok loadexec=ok dlsym=ok cpus=6 | clean tree 39831da, fresh cycle, all 11 stages ran, no crash; confirms the two probe fixes: loadexec=ok (restart got argv[0]=--ps4wine-loadexec, 2 s after the call) and cpus=6 (one spinner per core in mask 0x3f, all six at full speed, 464k-472k iterations each); every other field equals the 2026-10-30 00:06 run (frame mc 64/FXSAVE 320/FS 1152 via both handlers, cs32 ok, dlsym ok with modstart=0, audio open 0x809b0001, 2160p refused, flip 60.5 Hz); screen reported by user: amber twice, brief green, steady green; no capture stick (shot not taken); not tested: shot pixel, audio output; 20261030-001125-a.log
2026-10-30 01:01 | b | build 209acfd+dirty | PASS (no shot) | PS4WINE b triangle frames=300 api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1 build=209acfd+dirty edyn3=1 desc_idx=1 timeline=1 bda=1 cbc=1 dce=1 cond_render=0 indirect_count=0 exts=194 heap0_mib=661 max_alloc_mib=4095 swapchain=1920x1080 fmt=37 fps=59.9 gpu_hang=0 err=- | first launch of the triangle (title PSWN00002), screen reported by user: green triangle; RADV ORBIS device "PlayStation 4 Liverpool" api 1.3.359 driver 0x06802063, 194 device extensions; mesa-ps4 1a59cc1 + patches/mesa-ps4/0001 confirmed on console: cond_render=0 indirect_count=0, neither extension in the dump; heaps 661 MiB host (flags 0x0) + 1322 MiB device-local from the default 1024 MiB arena of a 4608 MiB direct pool, maxMemoryAllocationSize reports 4095 MiB (larger than either heap); surface formats 37/43 (RGBA), 1920x1080, 4 images; 300 frames FIFO at 59.9 fps, no hang, no fault; the line came via netlog (capture stopped on the match before klog's copy); pixel not tested (no capture stick), nor shot.sh's MJPEG 1920x1080 pin; 20261030-005903-b.log
2026-10-30 01:13 | b | build 01c7626+dirty | PASS (framebuffer) | PS4WINE b triangle frames=300 api=1.3 maintenance5=1 robustness2=1 gpl=1 dyn_rendering=1 xfb=1 build=01c7626+dirty edyn3=1 desc_idx=1 timeline=1 bda=1 cbc=1 dce=1 cond_render=0 indirect_count=0 exts=194 heap0_mib=661 max_alloc_mib=4095 swapchain=1920x1080 fmt=37 fps=59.9 gpu_hang=0 err=- fb=ok | pixel rules checked on the FRAMEBUFFER, not the HDMI output: frame 300's swapchain image copied back by the title (vkCmdCopyImageToBuffer) to /data/ps4-wine/shot.raw, fetched over FTP by fbshot.sh and read as R,G,B,A (VideoOut's A8B8G8R8 order); 960,540 = 0,255,0 and the new orange marker 240,135 = 255,128,0 exactly (title-side and host-side), so red/blue are in scan-out order in memory; wsi_orbis reports ZERO COPY (the 4 swapchain images are the registered A8B8G8R8_SRGB linear scan-out buffers), so this is the memory VideoOut flips, but scan-out, HDMI and TV path are untested; dump 8294400 bytes written in 154 ms, fps still 59.9; everything else equals the 00:59 run; screen reported by user: green triangle with an orange square top left (orange on the TV, so no red/blue swap after the framebuffer either, by eye); the HDMI pixel rule (capture stick) is still owed; 20261030-011110-b.log; 20261030-011329-b-fb.png

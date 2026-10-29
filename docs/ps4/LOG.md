# Console run log

One line per launch on the PS4, appended by hand from the output of
`scripts/ps4/check.sh <letter>` (or by hand when no check applies). Raw logs
and screenshots live under `logs/` (gitignored) and are named in the line.

## Line format

```
YYYY-MM-DD HH:MM | <a-h> | build <sha7>[+dirty] | PASS|FAIL|CRASH|NOLOG | <check line or first failure> | <notes; logs/<ts>-<label>.log; logs/<ts>-<label>.png>
```

- `build`: the short commit of the tree that produced the package (`scripts/ps4/common.sh` `build_id`), `+dirty` when uncommitted changes were in it.
- `PASS` / `FAIL`: the milestone check's verdict on the captured `PS4WINE` line.
- `CRASH`: the title ended with a kernel fault or CE-34878-0 before its check line (quote the `fault` record or the klog exception line).
- `NOLOG`: no `PS4WINE` line arrived within the timeout (say whether klog, netlog or both were silent).
- Fifth column: the exact `PS4WINE ...` line, or the first failing field, or the first error line.
- Sixth column: what changed since the previous run, what was and was not tested, file names of the raw log and screenshot.

Example (not a real run):

```
2026-11-02 21:14 | a | build 3f2a9c1 | PASS | PS4WINE a hello ok build=3f2a9c1 direct_mib=4464 flex_mib=384 reserve_gib=16 jit=ok | first boot of the samples layout; sysarch not probed yet; logs/20261102-2114-a.log
```

## Runs

2026-10-30 00:06 | a | build 97fcc7c+dirty | PASS | PS4WINE a hello ok build=97fcc7c+dirty direct_mib=4464 flex_mib=437 reserve_gib=16 jit=ok sysarch=fs+gs frame_mc=64 frame_fx=320 frame_fs=1152 cs32=ok loadexec=noargs dlsym=ok cpus=4 | first launch, all 11 stages ran, no crash; screen reported by user: amber, brief green, steady green after the LoadExec restart; no capture stick (shot not taken); netlog and klog both received; loadexec=noargs is a probe bug: the restart got argv[0]=--ps4wine-loadexec (argc=1), the probe scanned from argv[1], so LoadExec with arguments works; cpus=4 is a test artefact: cpu_mask=0x3f and sysconf=6, threads 6/7 were refused affinity (0x80020001) and shared cores 1/4; frame offsets equal prospero-win's PS5 values (mc 64, FXSAVE 320, FS base 1152, cs 0x43, both sigaction and sceKernelInstallExceptionHandler); far jump to 0x33 and back ran 32-bit code; rdfsbase SIGILL; getppid stub has syscall at +10; modstart=0 (PRX constructor did not run) with dlsym ok; audio open 0x809b0001; 2160p buffers refused 0x80290005, 720p ok; flip 60.7 Hz; not tested: shot pixel, audio output, VideoOut sizes beyond the two; 20261030-000148-a.log

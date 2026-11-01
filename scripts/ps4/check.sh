#!/usr/bin/env bash
# check.sh: the one pass/fail check per milestone (docs/ps4/MILESTONES.md).
# Reads the title's "PS4WINE <letter> key=value ..." line from a logs.sh file,
# applies the milestone's rule, runs the pixel check where the milestone has
# one, and prints the line for docs/ps4/LOG.md. Exit 0 PASS, 1 FAIL/NOLOG,
# 2 part of the rule is not implemented yet.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/check.sh <a|b|c|d|d1..d4|e|e1..e3|f|f1|f2|p1..p5|p5w|p6|g|h> [--log FILE] [--shot FILE] [--no-shot | --fb] [--note TEXT]

  --log FILE   log captured by logs.sh (default: the newest logs/*-<letter>.log, else newest logs/*.log)
  --shot FILE  use this image for the pixel check instead of capturing one now
  --no-shot    skip the pixel check of the milestones that have one (b, d1, d2, d4, d, e1, e, f2): a pass is then
               reported as "PASS (no shot)"; the other milestones are unaffected
  --fb         take the pixels from the title's framebuffer readback instead of the HDMI capture:
               requires fb=ok in its PS4WINE line, fetches it with fbshot.sh (or uses --shot FILE,
               a PNG fbshot.sh made), and reports a pass as "PASS (framebuffer)": the rendered frame
               is checked, the HDMI output is not
  --note TEXT  free text for the last column of the LOG.md line
  --audio WAV --audio-window S:D
               p5: the WAV beside the launch's recording (view.sh --record) and the window, start S
               and length D in seconds from the recording's start, that holds the scripted tail
  --no-audio   p5: skip the HDMI audio rule ("PASS (no audio)"; the rule is still owed)
Pixel rules: b  960,540 = 0,255,0 (triangle centre; CHECK_B_RGB overrides) and 240,135 = 255,128,0
                (orange marker: swapped red and blue fail it); d1 the same two on the title's VideoOut
                test pattern (framebuffer only: use --fb); e  960,540 = CHECK_E_RGB.
             d2 960,540 = 0,255,0 and 780,410 = 255,128,0 (gdi64.exe's window on the framebuffer);
             d4 640,298 = 255,255,0 (winemine's smiley) and 634,390 = 0,0,0 (the clicked cell, opened).
             e1 960,540 = 0,255,255 (the title's Vulkan clear) and 240,135 = 255,128,0 (its marker square),
                from RADV's own readback of the scan-out (ORBIS_WSI_SHOT, patches/mesa-ps4/0002; use --fb).
             e3 960,540 = 255,0,0 (vk64.exe's clear) and 240,135 = 0,255,0 (its square), the same readback.
             e  960,540 = CHECK_E_RGB (default 255,255,0: d3d11tri64.exe's triangle) and 240,135 = 0,0,255
                (its clear), the same readback.
             f2 d2's two pixels: gdi64.exe's window built for i686, inside wow32.exe (HDMI or --fb).
Sub-steps of d (docs/ps4/HANDOFF-d.md): d1 binding + VideoOut + pad + hello.exe; d2 win32u + GDI
and d3 fonts, both from one gdi64.exe launch (check each with the same --log); d4 winemine with a
scripted click; d5 is milestone d's own rule (check.sh d: the DS4 play after d4's click).
Sub-steps of e (docs/ps4/HANDOFF-e.md): e1 RADV's libvulkan.prx driven by the title (device, DXVK's
features, the display handed over, a 1920x1080 swapchain scanned out) + hello.exe; e2 winevulkan
and Wine's Vulkan, and e3 win32u's surface with the hand-over and a Win32 swapchain, both from one
vk64.exe launch (check each with the same --log).
Sub-steps of f (docs/ps4/HANDOFF-f.md): f1 wowprospero.prx bound and wow32.exe's checks (x87/SSE2, a
second thread, SEH of guest faults) on the translator, no unresolved fault; f2 its GDI picture through
wow64win; both from one wow32.exe launch (check each with the same --log). f is milestone f's own rule:
Space Cadet Pinball played with the DS4 (C:\Pinball, plan f), no pixel rule (an HDMI frame of the table
is the evidence, taken with shot.sh while it runs).
Phase p (docs/ps4/HANDOFF-p.md), between f and g: p1 measures Space Cadet Pinball's attract mode over a
fixed 60 s segment with the pad unused (plan p1): seg_s>=60, inputs=0, presents>=600 (a sanity floor),
no unresolved fault, and every guest/copy/keep/flip histogram field (min, avg, p95, max) a number. No
performance threshold. p2: native WoW64, correctness only: native_caps=7 (Wine's readiness export), cpu=native, the
segment completed with no input and no unresolved fault; the title's own probe (probe_caps, altstack53, ...) and
the guest times are recorded, not gated. p3: the same segment on A8R8G8B8_SRGB scan-out buffers (present_path=vo720 or vo1080,
vo_register=ok, vo_flip=ok) with copy_us_avg <= 11647 (T3, written from p1 before p3 ran). p4: three buffers
and the asynchronous flip (present_mode=async, buffers=3) with shown_hz >= 59 and flip_errors=0. p3 and p4
also read the title's test pattern over HDMI, 960,540 = 0,255,0 and 240,135 = 255,128,0: a frame
of the launch's recording given with --shot (the pattern is on screen for 5 s before Wine starts; a live
capture or the framebuffer readback cannot show it), or --no-shot.
p5w, a step of p5 (plan p5w, the fork's tests/wine_wincb.c): windows made on the main thread and on new
threads, every case on both (main_ok and new_ok all made), the Message class's procedure called directly on
each (direct_main=1, direct_new=1), a CBT hook called on each (cbt_main>=1, cbt_new>=1), a new thread's send
to a window of the main thread answered (cross=ok), exit=0 and no unresolved fault. The thread stacks' cost
(hold_flex_kib, flex_mib*, threads_*, stack_floor_mib) is recorded, not gated, in p5w's line and p5's.
p6, the thread stacks before g (plan p6: libkernel's own stacks probed, then p5w's wincb32.exe whose 8 hold
threads come twice): p5w's rule, no failed create, and at most 8192 KiB of flexible memory for each set of 8
live threads (hold_flex_kib, and hold2_flex_kib for the second 8 after the first have ended): 1 MiB a thread,
twice the 512 KiB the layer's small policy gives. stack_policy, threads_kept/small/keep_refused, hold_back_kib
and the probe's sp_lib_* are recorded, not gated. e's line carries the same thread fields and libvulkan.prx's
own (vk_threads_created, vk_stack_floor_kib), recorded.
p5's underruns are the audio driver's (the fork's wine/wineps5, src/pw_audio_mix.h): stretches of grains in
which a started stream's ring ran out, ended by more data while it was still started (silence inside a sound).
A stretch ended by a stop is a drain (the sound's end), and a pause between grains a gap; both are recorded,
not gated.
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
MS="$1"; shift
LOG=""; SHOT=""; NOSHOT=0; FB=0; NOTE=""; AUDIO=""; AUDIO_WINDOW=""; NOAUDIO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOG="$2"; shift 2 ;;
        --shot) SHOT="$2"; shift 2 ;;
        --no-shot) NOSHOT=1; shift ;;
        --fb) FB=1; shift ;;
        --note) NOTE="$2"; shift 2 ;;
        --audio) AUDIO="$2"; shift 2 ;;
        --audio-window) AUDIO_WINDOW="$2"; shift 2 ;;
        --no-audio) NOAUDIO=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
case "$MS" in a|b|c|d|d1|d2|d3|d4|e|e1|e2|e3|f|f1|f2|p1|p2|p3|p4|p5|p5w|p6|g|h) ;; -h|--help) usage; exit 0 ;; *) usage; exit 1 ;; esac
[ "$NOSHOT" = 1 ] && [ "$FB" = 1 ] && { log "--no-shot and --fb exclude each other"; usage; exit 1; }
if [ "$MS" = p5 ]; then
    { [ -n "$AUDIO" ] && [ -n "$AUDIO_WINDOW" ]; } || [ "$NOAUDIO" = 1 ] ||
        die "p5: give --audio WAV --audio-window S:D (the recording's sound and the tail's window) or --no-audio"
fi
if [[ "$MS" == p[34] ]]; then
    [ "$FB" = 0 ] || die "$MS: the pattern is checked over HDMI only (--shot FRAME from the recording)"
    [ -n "$SHOT" ] || [ "$NOSHOT" = 1 ] || die "$MS: give --shot FRAME (the recording's frame of the test pattern) or --no-shot"
fi

if [ -z "$LOG" ]; then
    LOG="$(ls -t "$LOGS_DIR"/*-"$MS".log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || LOG="$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || die "no log file under $LOGS_DIR; run logs.sh first"
fi
[ -f "$LOG" ] || die "no such log: $LOG"
NOW="$(date '+%Y-%m-%d %H:%M')"
BID="$(build_id)"

# The PS4WINE line for this milestone, stripped of the logs.sh prefix, klog's "<118>[...]" tag and
# the diagnostics record's "<seq>\t<ns>\tINFO\t" columns (its copy of the line arrives over netlog too).
# The last line, or a longer copy of it: klog keeps 512 bytes of a line and the diagnostics record 1024,
# and the p lines are longer than both, so a cut copy arriving last is replaced by the longest line it
# begins (the raw netlog copy is whole). A different line arriving last (a's after its restart) stays.
LINE="$(grep -E "PS4WINE $MS " "$LOG" | sed -E 's/^[0-9:]+ [KN] //; s/^<[0-9]+>\[[^]]*\] *//; s/^[0-9]+\t[0-9]+\t[A-Z]+\t//' |
        awk '{ all[NR] = $0 } END { if (!NR) exit; line = all[NR]
              for (i = 1; i < NR; i++) if (length(all[i]) > length(line) && index(all[i], all[NR]) == 1) line = all[i]
              print line }' || true)"
emit() { printf '%s | %s | build %s | %s | %s | %s\n' "$NOW" "$MS" "$BID" "$1" "$2" "${NOTE:+$NOTE; }$(basename "$LOG")${SHOT:+; $(basename "$SHOT")}"; }
if [ -z "$LINE" ]; then
    FIRST_ERR="$(grep -iE '\b(exception|fault|panic|abort)\b|CE-3' "$LOG" | head -n1 || true)"
    # d1-d3 and e1 record each stage as it ends ("PW_MS stage=<name> ...", "PW_D1" before d2): name the ones that arrived.
    STAGES=""
    if [[ "$MS" == d[123] || "$MS" == e || "$MS" == e[123] || "$MS" == f || "$MS" == f[12] || "$MS" == p[1-6] || "$MS" == p5w ]]; then
        STAGES="$(grep -oE 'PW_(D1|MS) stage=[a-z0-9_]+ ' "$LOG" | sed -E 's/PW_(D1|MS) stage=//; s/ $//' | awk '!seen[$0]++' | paste -sd, - || true)"
        STAGES="; stage records: ${STAGES:-none}"
    fi
    if [ -n "$FIRST_ERR" ]; then emit CRASH "$FIRST_ERR$STAGES"; else emit NOLOG "no 'PS4WINE $MS' line in $(basename "$LOG")$STAGES"; fi
    exit 1
fi

declare -A F=()
for kv in $LINE; do case "$kv" in *=*) F["${kv%%=*}"]="${kv#*=}" ;; esac; done
[ -n "${F[build]:-}" ] && BID="${F[build]}"
FAILS=()
req() { # req KEY OP VALUE   OP: ge le eq in (VALUE: a comma list)
    local k="$1" op="$2" want="$3" have="${F[$1]:-}"
    if [ -z "$have" ]; then FAILS+=("$k missing"); return; fi
    case "$op" in
        in) [[ ",$want," == *",$have,"* ]] || FAILS+=("$k=$have not in {$want}") ;;
        ge) [ "${have%%.*}" -ge "$want" ] 2>/dev/null || FAILS+=("$k=$have < $want") ;;
        le) [ "${have%%.*}" -le "$want" ] 2>/dev/null || FAILS+=("$k=$have > $want") ;;
        eq) [ "$have" = "$want" ] || FAILS+=("$k=$have != $want") ;;
    esac
}
word() { [[ " $LINE " == *" $1 "* ]] || FAILS+=("missing word '$1'"); }
num() { # num KEY...: each present and a non-negative integer (a histogram field; "-" is empty)
    local k
    for k in "$@"; do
        [[ "${F[$k]:-}" =~ ^[0-9]+$ ]] || FAILS+=("$k=${F[$k]:-missing} not a number")
    done
}
all() { # all KEY: an "N/M" count with every one of M > 0 (every import slot bound)
    local have="${F[$1]:-}"
    if [ -z "$have" ]; then FAILS+=("$1 missing"); return; fi
    [[ "$have" =~ ^([0-9]+)/([0-9]+)$ ]] && [ "${BASH_REMATCH[2]}" -gt 0 ] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] ||
        FAILS+=("$1=$have not all")
}

PIXELS=(); HAS_PIXEL=0   # "X,Y=R,G,B" rules, all read from one image
case "$MS" in
    a) word hello; word ok; req direct_mib ge 4000; req jit eq ok ;;
    b) word triangle; req frames ge 60; req api eq 1.3; req maintenance5 eq 1; req robustness2 eq 1; req gpl eq 1; req dyn_rendering eq 1; req xfb eq 1
       HAS_PIXEL=1; PIXELS=("960,540=${CHECK_B_RGB:-0,255,0}" "240,135=255,128,0") ;;
    c) word hello.exe; req server eq inprocess; req exit eq 0
       [[ "$LINE" == *'stdout="Hello from PE64"'* ]] || FAILS+=("stdout mismatch") ;;
    d) word winemine; req frames ge 600; req inputs ge 10; req refused eq 0; req board_opened eq 1; req fb eq ok
       # d4's pixels (the readback is kept right after the title's scripted click, before the DS4 play).
       HAS_PIXEL=1; PIXELS=("640,298=255,255,0" "634,390=0,0,0") ;;
    d1) req bind in import,thunk; req videoout eq ok; req fb eq ok; req hello eq ok
        HAS_PIXEL=1; PIXELS=("960,540=0,255,0" "240,135=255,128,0") ;;
    d2) word gdi; req win32u eq ok; req pixel eq ff8000; req exit eq 0
        # gdi64.exe's window: orange 400x300 at 200,150 of the 800x600 desktop, green 200x150 inside at
        # 100,75; the desktop centred on 1920x1080 at 560,240 (scale 1).
        HAS_PIXEL=1; PIXELS=("960,540=0,255,0" "780,410=255,128,0") ;;
    d3) word fonts; req n ge 1; req tahoma eq 1; req text_px ge 50; req exit eq 0 ;;
    d4) word winemine; req frames ge 2; req board_opened eq 1; req refused eq 0; req fb eq ok
        # From the host reference run (tools/test_wine_ps5_driver.sh --click 80,153 winemine): winemine at 0,0 of
        # the 800x600 desktop (centred at 560,240); its smiley's yellow at 80,58 and the clicked middle cell's
        # inside at 74,150, opened (0,0,0; closed it is 0,128,0).
        HAS_PIXEL=1; PIXELS=("640,298=255,255,0" "634,390=0,0,0") ;;
    e) word d3d11; req frames ge 300; req gpu_hang eq 0; req swapchain eq 1920x1080
       # d3d11tri64.exe (the fork's tests/wine_d3d11tri64.c): its yellow triangle over the centre and the blue
       # clear at 240,135, fixed from the host reference run (DXVK 2.6.2 on lavapipe through the PS4 user
       # driver's headless surface: px_c=ffff00 px_m=0000ff) before the first console run.
       HAS_PIXEL=1; PIXELS=("960,540=${CHECK_E_RGB:-255,255,0}" "240,135=0,0,255") ;;
    e1) word vk; req vk_load eq ok; all vk_bound; req inst eq ok; req api eq 1.3; req maintenance5 eq 1; req robustness2 eq 1
        req gpl eq 1; req dyn_rendering eq 1; req xfb eq 1; req release eq ok; req present eq ok; req frames ge 300
        req gpu_hang eq 0; req swapchain eq 1920x1080; req fb eq ok; req hello eq ok
        # The title's own frames through RADV (native/orbis/pw_vk_stage_orbis.h): cyan, the orange square on 240,135.
        HAS_PIXEL=1; PIXELS=("960,540=0,255,255" "240,135=255,128,0") ;;
    e2) word vk64; req inst eq ok; req api eq 1.3; req exts_dxvk eq ok; req dev eq ok; req submit eq ok
        all wv_bound; all w32u_bound ;;
    e3) word vkclear; req release eq ok; req surface eq ok; req present eq ok; req frames ge 300; req gpu_hang eq 0
        req swapchain eq 1920x1080; req fb eq ok
        # vk64.exe's frames (tests/wine_vk64.c in the fork): red, the green square on 240,135.
        HAS_PIXEL=1; PIXELS=("960,540=255,0,0" "240,135=0,255,0") ;;
    f1) word hello32; req cpu eq translator; all wow_bound; req fp eq ok; req thread eq ok; req seh eq ok
        req faults_unresolved eq 0; req exit eq 0 ;;
    f2) word gdi32; req win32u eq ok; req pixel eq ff8000; req window eq ok
        # gdi64.exe's window built for i686 (wow32.exe's second part): d2's picture on the 800x600 desktop.
        HAS_PIXEL=1; PIXELS=("960,540=0,255,0" "780,410=255,128,0") ;;
    f) word pinball; req cpu eq translator; req frames ge 600; req faults_unresolved eq 0 ;;
    p1) word bench; word pinball; req cpu eq translator; req end eq segment; req seg_s ge 60; req inputs eq 0
        req presents ge 600; req faults_unresolved eq 0
        for h in guest_us copy_us keep_us flip_us; do num "${h}_min" "${h}_avg" "${h}_p95" "${h}_max"; done ;;
    p2) word bench; word pinball; req native_caps eq 7; req cpu eq native; req end eq segment; req seg_s ge 60
        req inputs eq 0; req faults_unresolved eq 0 ;;
    p5) word bench; word pinball; req audio_open eq ok; req audio_user eq system; req end eq segment; req seg_s ge 60
        req inputs eq 0; req faults_unresolved eq 0
        # G: Pinball's shortest WAV effect (SOUND112.WAV, 58 ms) is 10.9 grains of 256 frames at 48 kHz.
        req grains_nonzero ge 10; req underruns eq 0
        # The rate gate's branch, fixed when p4 passed (2026-11-01 18:40): p4's own rule on p4's path.
        req present_mode eq async; req shown_hz ge 59
        if [ "$NOAUDIO" = 0 ] && [ -n "$AUDIO" ]; then
            # D: the tail's window averages >= -30 dB on the stick's input; two silent PS4 recordings
            # measured -39.5 and -36.9 dB mean (peaks -25.9 and -19.5: the input is noisy, so the
            # mean, not the peak) before the first p5 run.
            mean="$(ffmpeg -hide_banner -nostats -ss "${AUDIO_WINDOW%%:*}" -t "${AUDIO_WINDOW#*:}" -i "$AUDIO" \
                    -af volumedetect -f null - 2>&1 | sed -n 's/.*mean_volume: \(-*[0-9.]*\) dB.*/\1/p' | tail -n1)"
            if [ -z "$mean" ]; then FAILS+=("audio: no level read from $(basename "$AUDIO")")
            elif ! awk -v m="$mean" 'BEGIN { exit !(m >= -30) }'; then FAILS+=("audio mean ${mean} dB < -30 dB")
            else NOTE="${NOTE:+$NOTE; }HDMI audio mean ${mean} dB in ${AUDIO_WINDOW}"; fi
        fi ;;
    p5w) # Written before the first p5w launch (docs/ps4/HANDOFF-p.md): every window made on every thread.
         word wincb; all main_ok; all new_ok; req direct_main eq 1; req direct_new eq 1; req cbt_main ge 1
         req cbt_new ge 1; req cross eq ok; req exit eq 0; req faults_unresolved eq 0 ;;
    p6) # Written before the first p6 launch (docs/ps4/HANDOFF-p.md): p5w's rule, then the stacks' cost.
        word stacks; all main_ok; all new_ok; req direct_main eq 1; req direct_new eq 1; req cbt_main ge 1
        req cbt_new ge 1; req cross eq ok; req exit eq 0; req faults_unresolved eq 0
        # 8 live threads at 1 MiB each: twice the small policy's 512 KiB (libkernel's thread object, TLS and
        # the 16 KiB granule on top). The floor took 98304 (p5w, 2026-11-01). The second 8 after the first
        # ended must cost no more: a leak fails here.
        req threads_create_failed eq 0; req hold_flex_kib le 8192; req hold2_flex_kib le 8192 ;;
    p3|p4) word bench; word pinball; req cpu eq translator; req end eq segment; req seg_s ge 60; req inputs eq 0
        req presents ge 600; req faults_unresolved eq 0; req vo_register eq ok; req vo_flip eq ok
        for h in guest_us copy_us flip_us; do num "${h}_min" "${h}_avg" "${h}_p95" "${h}_max"; done
        if [ "$MS" = p3 ]; then
            req present_path in vo720,vo1080; req copy_us_avg le 11647   # T3 (docs/ps4/HANDOFF-p.md, from p1)
        else
            req present_mode eq async; req buffers eq 3; req shown_hz ge 59; req flip_errors eq 0
        fi
        # The test pattern full-screen: its green centre -> 960,540, its orange marker at an eighth -> 240,135.
        HAS_PIXEL=1; PIXELS=("960,540=0,255,0" "240,135=255,128,0") ;;
    # g: fixed 2026-11-01 before the first g run (docs/ps4/HANDOFF-g.md: gameplay=1 is the user's mark).
    g) word vtmb; req batch eq 1; req gameplay eq 1; req crossings_per_frame le 2000; req fps_avg ge 20; req session_s ge 300; req faults_unresolved eq 0 ;;
    h) word vtmb; req session_s ge 1800; req fps_avg ge 20; req faults_unresolved eq 0; req saved eq 1; req loaded eq 1
       # TODO(milestone h): list /data/ps4-wine/prefix/drive_c/VTMB/Unofficial_Patch/save over FTP and require a save newer than the session start.
       log "h: the FTP save-file check is not implemented yet; the log fields are checked"; ;;
esac

if [ "$HAS_PIXEL" = 1 ] && [ "$NOSHOT" = 0 ]; then
    if [ "$FB" = 1 ] && [ "${F[fb]:-}" != ok ]; then
        FAILS+=("fb=${F[fb]:-missing}: no framebuffer readback from this run"); SHOT=""
    elif [ -z "$SHOT" ] && [ "$FB" = 1 ]; then
        SHOT="$("$SCRIPT_DIR/fbshot.sh" --label "$MS" | sed -n 's/^file=//p' || true)"
        [ -n "$SHOT" ] || FAILS+=("fb: fetching the readback failed")
    elif [ -z "$SHOT" ]; then
        SHOT="$LOGS_DIR/$(timestamp)-$MS.png"
        "$SCRIPT_DIR/shot.sh" --out "$SHOT" || { FAILS+=("pixel: no capture"); SHOT=""; }
    fi
    if [ -n "$SHOT" ]; then
        for rule in "${PIXELS[@]}"; do
            PR="$("$SCRIPT_DIR/shot.sh" --in "$SHOT" --pixel "${rule%%=*}" --expect-rgb "${rule#*=}" --tol "${CHECK_TOL:-60}" || true)"
            case "$PR" in *pixel-match*) ;; *) FAILS+=("pixel ${rule%%=*}: $(printf '%s' "${PR:-unreadable}" | sed 's/ file=[^ ]*//' | tr '\n' ' ')") ;; esac
        done
    fi
fi

if [ "${#FAILS[@]}" -eq 0 ]; then
    if [ "$MS" = p5 ] && [ "$NOAUDIO" = 1 ]; then emit "PASS (no audio)" "$LINE"
    elif [ "$HAS_PIXEL" = 1 ] && [ "$NOSHOT" = 1 ]; then emit "PASS (no shot)" "$LINE"
    elif [ "$HAS_PIXEL" = 1 ] && [ "$FB" = 1 ]; then emit "PASS (framebuffer)" "$LINE"
    else emit PASS "$LINE"; fi
    exit 0
else
    emit FAIL "${FAILS[*]} || $LINE"; exit 1
fi

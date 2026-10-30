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
usage: scripts/ps4/check.sh <a|b|c|d|d1..d5|e|f|g|h> [--log FILE] [--shot FILE] [--no-shot | --fb] [--note TEXT]

  --log FILE   log captured by logs.sh (default: the newest logs/*-<letter>.log, else newest logs/*.log)
  --shot FILE  use this image for the pixel check instead of capturing one now
  --no-shot    skip the pixel check of the milestones that have one (b, d1, e): a pass is then
               reported as "PASS (no shot)"; the other milestones are unaffected
  --fb         take the pixels from the title's framebuffer readback instead of the HDMI capture:
               requires fb=ok in its PS4WINE line, fetches it with fbshot.sh (or uses --shot FILE,
               a PNG fbshot.sh made), and reports a pass as "PASS (framebuffer)": the rendered frame
               is checked, the HDMI output is not
  --note TEXT  free text for the last column of the LOG.md line
Pixel rules: b  960,540 = 0,255,0 (triangle centre; CHECK_B_RGB overrides) and 240,135 = 255,128,0
                (orange marker: swapped red and blue fail it); d1 the same two on the title's VideoOut
                test pattern (framebuffer only: use --fb); e  960,540 = CHECK_E_RGB.
             d2 960,540 = 0,255,0 and 780,410 = 255,128,0 (gdi64.exe's window on the framebuffer);
             d4 640,298 = 255,255,0 (winemine's smiley) and 634,390 = 0,0,0 (the clicked cell, opened).
Sub-steps of d (docs/ps4/HANDOFF-d.md): d1 binding + VideoOut + pad + hello.exe; d2 win32u + GDI
and d3 fonts, both from one gdi64.exe launch (check each with the same --log); d4 winemine with a
scripted click; d5 is not implemented yet (exit 2).
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
MS="$1"; shift
LOG=""; SHOT=""; NOSHOT=0; FB=0; NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOG="$2"; shift 2 ;;
        --shot) SHOT="$2"; shift 2 ;;
        --no-shot) NOSHOT=1; shift ;;
        --fb) FB=1; shift ;;
        --note) NOTE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
case "$MS" in a|b|c|d|d1|d2|d3|d4|d5|e|f|g|h) ;; -h|--help) usage; exit 0 ;; *) usage; exit 1 ;; esac
[ "$NOSHOT" = 1 ] && [ "$FB" = 1 ] && { log "--no-shot and --fb exclude each other"; usage; exit 1; }
case "$MS" in d5) log "$MS: the rule is written in docs/ps4/HANDOFF-d.md and not implemented yet"; exit 2 ;; esac

if [ -z "$LOG" ]; then
    LOG="$(ls -t "$LOGS_DIR"/*-"$MS".log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || LOG="$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || die "no log file under $LOGS_DIR; run logs.sh first"
fi
[ -f "$LOG" ] || die "no such log: $LOG"
NOW="$(date '+%Y-%m-%d %H:%M')"
BID="$(build_id)"

# The last PS4WINE line for this milestone, stripped of the logs.sh prefix, klog's "<118>[...]" tag
# and the diagnostics record's "<seq>\t<ns>\tINFO\t" columns (its copy of the line arrives over netlog too).
LINE="$(grep -E "PS4WINE $MS " "$LOG" | tail -n1 | sed -E 's/^[0-9:]+ [KN] //; s/^<[0-9]+>\[[^]]*\] *//; s/^[0-9]+\t[0-9]+\t[A-Z]+\t//' || true)"
emit() { printf '%s | %s | build %s | %s | %s | %s\n' "$NOW" "$MS" "$BID" "$1" "$2" "${NOTE:+$NOTE; }$(basename "$LOG")${SHOT:+; $(basename "$SHOT")}"; }
if [ -z "$LINE" ]; then
    FIRST_ERR="$(grep -iE '\b(exception|fault|panic|abort)\b|CE-3' "$LOG" | head -n1 || true)"
    # d1-d3 record each stage as it ends ("PW_MS stage=<name> ...", "PW_D1" before d2): name the ones that arrived.
    STAGES=""
    if [[ "$MS" == d[123] ]]; then
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

PIXELS=(); HAS_PIXEL=0   # "X,Y=R,G,B" rules, all read from one image
case "$MS" in
    a) word hello; word ok; req direct_mib ge 4000; req jit eq ok ;;
    b) word triangle; req frames ge 60; req api eq 1.3; req maintenance5 eq 1; req robustness2 eq 1; req gpl eq 1; req dyn_rendering eq 1; req xfb eq 1
       HAS_PIXEL=1; PIXELS=("960,540=${CHECK_B_RGB:-0,255,0}" "240,135=255,128,0") ;;
    c) word hello.exe; req server eq inprocess; req exit eq 0
       [[ "$LINE" == *'stdout="Hello from PE64"'* ]] || FAILS+=("stdout mismatch") ;;
    d) word winemine; req frames ge 600; req inputs ge 10; req refused eq 0; req board_opened eq 1 ;;
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
       HAS_PIXEL=1; PIXELS=("960,540=${CHECK_E_RGB:-}"); [ -n "${CHECK_E_RGB:-}" ] || { [ "$NOSHOT" = 1 ] || { log "set CHECK_E_RGB=R,G,B to the sample's triangle colour (decided when the sample is chosen in milestone e)"; exit 2; }; } ;;
    f) word pinball; req cpu eq translator; req frames ge 600; req faults_unresolved eq 0 ;;
    g) word hl2; req batch eq 1; req crossings_per_frame le 2000; req fps_avg ge 20; req session_s ge 300; req faults_unresolved eq 0 ;;
    h) word vtmb; req session_s ge 1800; req fps_avg ge 20; req faults_unresolved eq 0; req saved eq 1; req loaded eq 1
       # TODO(milestone h): list /data/ps4-wine/prefix/.../SAVE over FTP and require a save newer than the session start.
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
    if [ "$HAS_PIXEL" = 1 ] && [ "$NOSHOT" = 1 ]; then emit "PASS (no shot)" "$LINE"
    elif [ "$HAS_PIXEL" = 1 ] && [ "$FB" = 1 ]; then emit "PASS (framebuffer)" "$LINE"
    else emit PASS "$LINE"; fi
    exit 0
else
    emit FAIL "${FAILS[*]} || $LINE"; exit 1
fi

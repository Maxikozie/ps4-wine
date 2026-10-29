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
usage: scripts/ps4/check.sh <a|b|c|d|e|f|g|h> [--log FILE] [--shot FILE] [--no-shot] [--note TEXT]

  --log FILE   log captured by logs.sh (default: the newest logs/*-<letter>.log, else newest logs/*.log)
  --shot FILE  use this image for the pixel check instead of capturing one now
  --no-shot    skip the pixel check (the result is then at most "PASS (no shot)")
  --note TEXT  free text for the last column of the LOG.md line
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
MS="$1"; shift
LOG=""; SHOT=""; NOSHOT=0; NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOG="$2"; shift 2 ;;
        --shot) SHOT="$2"; shift 2 ;;
        --no-shot) NOSHOT=1; shift ;;
        --note) NOTE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
case "$MS" in a|b|c|d|e|f|g|h) ;; -h|--help) usage; exit 0 ;; *) usage; exit 1 ;; esac

if [ -z "$LOG" ]; then
    LOG="$(ls -t "$LOGS_DIR"/*-"$MS".log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || LOG="$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -n1 || true)"
    [ -n "$LOG" ] || die "no log file under $LOGS_DIR; run logs.sh first"
fi
[ -f "$LOG" ] || die "no such log: $LOG"
NOW="$(date '+%Y-%m-%d %H:%M')"
BID="$(build_id)"

# The last PS4WINE line for this milestone, stripped of the logs.sh prefix and klog's "<118>[...]" tag.
LINE="$(grep -E "PS4WINE $MS " "$LOG" | tail -n1 | sed -E 's/^[0-9:]+ [KN] //; s/^<[0-9]+>\[[^]]*\] *//' || true)"
emit() { printf '%s | %s | build %s | %s | %s | %s\n' "$NOW" "$MS" "$BID" "$1" "$2" "${NOTE:+$NOTE; }$(basename "$LOG")${SHOT:+; $(basename "$SHOT")}"; }
if [ -z "$LINE" ]; then
    FIRST_ERR="$(grep -iE 'exception|fault|CE-3|panic|abort' "$LOG" | head -n1 || true)"
    if [ -n "$FIRST_ERR" ]; then emit CRASH "$FIRST_ERR"; else emit NOLOG "no 'PS4WINE $MS' line in $(basename "$LOG")"; fi
    exit 1
fi

declare -A F=()
for kv in $LINE; do case "$kv" in *=*) F["${kv%%=*}"]="${kv#*=}" ;; esac; done
[ -n "${F[build]:-}" ] && BID="${F[build]}"
FAILS=()
req() { # req KEY OP VALUE   OP: ge le eq
    local k="$1" op="$2" want="$3" have="${F[$1]:-}"
    if [ -z "$have" ]; then FAILS+=("$k missing"); return; fi
    case "$op" in
        ge) [ "${have%%.*}" -ge "$want" ] 2>/dev/null || FAILS+=("$k=$have < $want") ;;
        le) [ "${have%%.*}" -le "$want" ] 2>/dev/null || FAILS+=("$k=$have > $want") ;;
        eq) [ "$have" = "$want" ] || FAILS+=("$k=$have != $want") ;;
    esac
}
word() { [[ " $LINE " == *" $1 "* ]] || FAILS+=("missing word '$1'"); }

PIXEL_RGB=""
case "$MS" in
    a) word hello; word ok; req direct_mib ge 4000; req jit eq ok ;;
    b) word triangle; req frames ge 60; req api eq 1.3; req maintenance5 eq 1; req robustness2 eq 1; req gpl eq 1; req dyn_rendering eq 1; req xfb eq 1
       PIXEL_RGB="${CHECK_B_RGB:-0,255,0}" ;;
    c) word hello.exe; req server eq inprocess; req exit eq 0
       [[ "$LINE" == *'stdout="Hello from PE64"'* ]] || FAILS+=("stdout mismatch") ;;
    d) word winemine; req frames ge 600; req inputs ge 10; req refused eq 0; req board_opened eq 1 ;;
    e) word d3d11; req frames ge 300; req gpu_hang eq 0; req swapchain eq 1920x1080
       PIXEL_RGB="${CHECK_E_RGB:-}"; [ -n "$PIXEL_RGB" ] || { [ "$NOSHOT" = 1 ] || { log "set CHECK_E_RGB=R,G,B to the sample's triangle colour (decided when the sample is chosen in milestone e)"; exit 2; }; } ;;
    f) word pinball; req cpu eq translator; req frames ge 600; req faults_unresolved eq 0 ;;
    g) word hl2; req batch eq 1; req crossings_per_frame le 2000; req fps_avg ge 20; req session_s ge 300; req faults_unresolved eq 0 ;;
    h) word vtmb; req session_s ge 1800; req fps_avg ge 20; req faults_unresolved eq 0; req saved eq 1; req loaded eq 1
       # TODO(milestone h): list /data/ps4-wine/prefix/.../SAVE over FTP and require a save newer than the session start.
       log "h: the FTP save-file check is not implemented yet; the log fields are checked"; ;;
esac

if [ -n "$PIXEL_RGB" ] && [ "$NOSHOT" = 0 ]; then
    if [ -n "$SHOT" ]; then PR="$("$SCRIPT_DIR/shot.sh" --in "$SHOT" --pixel 960,540 --expect-rgb "$PIXEL_RGB" --tol "${CHECK_TOL:-60}" || true)"
    else PR="$("$SCRIPT_DIR/shot.sh" --label "$MS" --pixel 960,540 --expect-rgb "$PIXEL_RGB" --tol "${CHECK_TOL:-60}" || true)"
         SHOT="$(printf '%s' "$PR" | sed -n 's/.*file=//p' | head -n1)"; fi
    case "$PR" in *pixel-match*) ;; *) FAILS+=("pixel: ${PR:-no capture}") ;; esac
fi

if [ "${#FAILS[@]}" -eq 0 ]; then
    emit PASS "$LINE"; exit 0
else
    emit FAIL "${FAILS[*]} || $LINE"; exit 1
fi

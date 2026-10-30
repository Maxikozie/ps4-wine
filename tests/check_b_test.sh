#!/usr/bin/env bash
# check_b_test.sh: run scripts/ps4/check.sh b against fixture logs and generated images, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_b_test.sh

Runs scripts/ps4/check.sh b on each tests/fixtures/b-*.log, with --no-shot and with --shot on two
generated 1920x1080 PNGs (green and red centre), and checks the exit code and the verdict column.
The PNGs exercise shot.sh's --in pixel path; the capture path needs the HDMI stick and is not tested.
Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# A black 1920x1080 frame with a 200x200 box of COLOUR around the centre pixel (960,540).
frame() { ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
              -vf "drawbox=x=860:y=440:w=200:h=200:color=$1:t=fill" -frames:v 1 "$2"; }
frame 0x00ff00 "$TMP/green.png"
frame 0xff0000 "$TMP/red.png"

# case <fixture> <expected exit> <expected verdict> <substring of the line or ""> [check.sh options...]
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    shift 4
    out="$("$ROOT/scripts/ps4/check.sh" b --log "$FIX/$fx" "$@" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s %s: exit %s (want %s): %s\n' "$fx" "$*" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s %s: %s\n' "$fx" "$*" "$want"
    fi
}

case_ b-pass.log  0 "PASS (no shot)" "gpl=1 dyn_rendering=1 xfb=1" --no-shot
case_ b-pass.log  0 PASS  "green.png" --shot "$TMP/green.png"
case_ b-pass.log  1 FAIL  "pixel: rgb=" --shot "$TMP/red.png"
case_ b-nogpl.log 1 FAIL  "gpl=0 != 1" --no-shot
case_ b-hang.log  1 FAIL  "frames=12 < 60" --no-shot
case_ b-nolog.log 1 NOLOG "" --no-shot           # VK_*_device_fault in the ext dump is not a crash

if [ "$fails" -ne 0 ]; then echo "check_b_test: $fails failure(s)"; exit 1; fi
echo "check_b_test: all passed"

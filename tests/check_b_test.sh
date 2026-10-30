#!/usr/bin/env bash
# check_b_test.sh: run scripts/ps4/check.sh b against fixture logs and generated images, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_b_test.sh

Runs scripts/ps4/check.sh b on each tests/fixtures/b-*.log, with --no-shot, with --shot on generated
1920x1080 PNGs (the expected frame, a red centre, red and blue swapped) and with --fb, and checks the
exit code and the verdict column. fbshot.sh --raw converts generated raw dumps in R,G,B,A and
B,G,R,A byte order. The capture path (HDMI stick) and the FTP fetch are not tested here.
Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# A black 1920x1080 frame: a 200x200 box of CENTRE around 960,540 and a 64x64 box of MARKER around
# 240,135, as probes/triangle.c draws them (triangle centre and orange marker). OUT's extension picks
# the format: .png, or .raw for rawvideo in PIXFMT byte order.
frame() { # frame CENTRE MARKER OUT [PIXFMT]
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
        -vf "drawbox=x=860:y=440:w=200:h=200:color=$1:t=fill,drawbox=x=208:y=103:w=64:h=64:color=$2:t=fill" \
        -frames:v 1 ${4:+-f rawvideo -pix_fmt $4} "$3"
}
# lavfi draws in YUV, so the colours come back a few steps off (253,0,0; 0,125,254): match loosely.
frame 0x00ff00 0xff8000 "$TMP/good.png"
frame 0xff0000 0xff8000 "$TMP/red.png"
frame 0x00ff00 0x0080ff "$TMP/swapped.png"      # what a BGRA scan-out of the good frame looks like
frame 0x00ff00 0xff8000 "$TMP/rgba.raw" rgba     # the bytes the title writes (VideoOut order)
frame 0x00ff00 0xff8000 "$TMP/bgra.raw" bgra     # the bytes a B8G8R8A8 swapchain would leave
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/rgba.raw" --out "$TMP/fb-rgba.png" >/dev/null 2>&1
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/bgra.raw" --out "$TMP/fb-bgra.png" >/dev/null 2>&1
head -c 1000 "$TMP/rgba.raw" > "$TMP/short.raw"
if "$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/short.raw" --out "$TMP/short.png" >/dev/null 2>&1; then
    echo "FAIL fbshot.sh accepted a truncated dump"; fails=$((fails + 1))
else echo "ok   fbshot.sh refuses a truncated dump"; fi

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
case_ b-pass.log  0 PASS  "good.png" --shot "$TMP/good.png"
case_ b-pass.log  1 FAIL  "pixel 960,540: rgb=25" --shot "$TMP/red.png"
case_ b-pass.log  1 FAIL  "pixel 240,135: rgb=0," --shot "$TMP/swapped.png"
case_ b-pass.log  0 "PASS (framebuffer)" "fb-rgba.png" --fb --shot "$TMP/fb-rgba.png"
case_ b-pass.log  1 FAIL  "pixel 240,135: rgb=0," --fb --shot "$TMP/fb-bgra.png"
case_ b-nofb.log  1 FAIL  "fb=err:open" --fb --shot "$TMP/fb-rgba.png"
case_ b-nogpl.log 1 FAIL  "gpl=0 != 1" --no-shot
case_ b-hang.log  1 FAIL  "frames=12 < 60" --no-shot
case_ b-nolog.log 1 NOLOG "" --no-shot           # VK_*_device_fault in the ext dump is not a crash

if [ "$fails" -ne 0 ]; then echo "check_b_test: $fails failure(s)"; exit 1; fi
echo "check_b_test: all passed"

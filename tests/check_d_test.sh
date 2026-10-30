#!/usr/bin/env bash
# check_d_test.sh: run scripts/ps4/check.sh d1 against fixture logs and generated framebuffer dumps, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_d_test.sh

Runs scripts/ps4/check.sh d1 on each tests/fixtures/d1-*.log (synthetic: written before the first d1
launch), with --fb on generated 1920x1080 dumps converted by fbshot.sh --raw (the title's test pattern
in R,G,B,A, and the same bytes read as B,G,R,A) and with --no-shot, and checks the exit code and the
verdict column: a pass, a recovered data-import fault that still passes, a resumed launch that passes,
a VideoOut hang, no binding method, stage records only (NOLOG naming the stages), a crash. d2-d5 must
exit 2 (rule not implemented). The FTP fetch is not tested here.
Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# pw_videoout_orbis_test_pattern: black, a 400x400 green square around 960,540, a 64x64 orange square
# around 240,135, as raw bytes in PIXFMT order.
pattern() { # pattern OUT PIXFMT
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
        -vf "drawbox=x=760:y=340:w=400:h=400:color=0x00ff00:t=fill,drawbox=x=208:y=103:w=64:h=64:color=0xff8000:t=fill" \
        -frames:v 1 -f rawvideo -pix_fmt "$2" "$1"
}
pattern "$TMP/rgba.raw" rgba
pattern "$TMP/bgra.raw" bgra
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/rgba.raw" --out "$TMP/fb-rgba.png" >/dev/null 2>&1
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/bgra.raw" --out "$TMP/fb-bgra.png" >/dev/null 2>&1

# case <milestone> <fixture> <expected exit> <expected verdict> <substring of the line or ""> [check.sh options...]
case_() {
    local ms="$1" fx="$2" want_rc="$3" want="$4" sub="$5" out rc=0
    shift 5
    out="$("$ROOT/scripts/ps4/check.sh" "$ms" --log "$FIX/$fx" "$@" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s %s %s: exit %s (want %s): %s\n' "$ms" "$fx" "$*" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s %s %s: %s\n' "$ms" "$fx" "$*" "${want:-exit $rc}"
    fi
}

case_ d1 d1-pass.log       0 "PASS (framebuffer)" "w32u_bound=89/89" --fb --shot "$TMP/fb-rgba.png"
case_ d1 d1-pass.log       1 FAIL  "pixel 240,135: rgb=0," --fb --shot "$TMP/fb-bgra.png"
case_ d1 d1-pass.log       0 "PASS (no shot)" "" --no-shot
case_ d1 d1-datafault.log  0 "PASS (framebuffer)" "data=fault" --fb --shot "$TMP/fb-rgba.png"
case_ d1 d1-resumed.log    0 "PASS (framebuffer)" "launches=2 resumed=bind_early" --fb --shot "$TMP/fb-rgba.png"
case_ d1 d1-vohang.log     1 FAIL  "fb=hang" --fb --shot "$TMP/fb-rgba.png"
case_ d1 d1-nobind.log     1 FAIL  "bind=none not in {import,thunk}" --no-shot
case_ d1 d1-stagesonly.log 1 NOLOG "stage records: bind_early,bind_lib,bind_import,bind_thunk" --no-shot
case_ d1 d1-crash.log      1 CRASH "stage records: bind_early,bind_lib,bind_import,bind_thunk,bind_data" --no-shot
for ms in d2 d3 d4 d5; do case_ "$ms" d1-pass.log 2 "" "" --no-shot; done

if [ "$fails" -ne 0 ]; then echo "check_d_test: $fails failure(s)"; exit 1; fi
echo "check_d_test: all passed"

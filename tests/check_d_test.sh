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
a VideoOut hang, no binding method, stage records only (NOLOG naming the stages), a crash. Then d2 and
d3 on tests/fixtures/d2-*.log (one gdi64.exe launch gives both lines) with a generated dump of
gdi64.exe's window on the centred 800x600 desktop: a pass, no fonts (d2 passes, d3 fails), a fault in
the program, stage records only. d4-d5 must exit 2 (rule not implemented). The FTP fetch is not
tested here.
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
# gdi64.exe's window as pw_ms_present shows it: the 800x600 desktop at 560,240 (black), the orange
# 400x300 window at 200,150 of it, the green 200x150 rectangle at 100,75 of the window.
window() { # window OUT PIXFMT
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
        -vf "drawbox=x=760:y=390:w=400:h=300:color=0xff8000:t=fill,drawbox=x=860:y=465:w=200:h=150:color=0x00ff00:t=fill" \
        -frames:v 1 -f rawvideo -pix_fmt "$2" "$1"
}
window "$TMP/win-rgba.raw" rgba
window "$TMP/win-bgra.raw" bgra
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/win-rgba.raw" --out "$TMP/win-rgba.png" >/dev/null 2>&1
"$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/win-bgra.raw" --out "$TMP/win-bgra.png" >/dev/null 2>&1

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
case_ d2 d2-pass.log       0 "PASS (framebuffer)" "w32u_dlsym=bound" --fb --shot "$TMP/win-rgba.png"
case_ d2 d2-pass.log       1 FAIL  "pixel 780,410: rgb=0," --fb --shot "$TMP/win-bgra.png"
case_ d2 d2-pass.log       1 FAIL  "pixel 780,410" --fb --shot "$TMP/fb-rgba.png"   # d1's pattern is no window
case_ d3 d2-pass.log       0 PASS  "tahoma=1 text_px=310"
case_ d2 d2-nofonts.log    0 "PASS (no shot)" "" --no-shot
case_ d3 d2-nofonts.log    1 FAIL  "tahoma=0 != 1"
case_ d2 d2-fault.log      1 FAIL  "win32u=fail != ok" --no-shot
case_ d3 d2-fault.log      1 FAIL  "exit=fault != 0"
case_ d2 d2-stagesonly.log 1 NOLOG "stage records: w32u_bind,ft_bind,display" --no-shot
for ms in d4 d5; do case_ "$ms" d1-pass.log 2 "" "" --no-shot; done

if [ "$fails" -ne 0 ]; then echo "check_d_test: $fails failure(s)"; exit 1; fi
echo "check_d_test: all passed"

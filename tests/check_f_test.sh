#!/usr/bin/env bash
# check_f_test.sh: run scripts/ps4/check.sh f1 and f2 against fixture logs and generated framebuffer dumps, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_f_test.sh

Runs scripts/ps4/check.sh f1 and f2 on each tests/fixtures/f1-*.log and f2-*.log (synthetic: written
before the first f1 launch; one wow32.exe launch gives both lines) and checks the exit code and the
verdict column. f1: a pass, a wowprospero slot not bound, a failed SEH catch (f2 still passes: its rule
does not read the program's exit), the program on the native CPU instead of the translator (cpu=none), an
unresolved fault, stage records only (NOLOG naming the stages). f2, with --fb on generated 1920x1080
dumps of gdi64.exe's window (as check_d_test.sh makes them, converted by fbshot.sh --raw; R,G,B,A and the
same bytes read as B,G,R,A) and with --no-shot: a pass, swapped red and blue, no window in the picture,
no window created. Then f (milestone f's own rule, Space Cadet Pinball) on tests/fixtures/f-*.log: a pass,
the native CPU instead of the translator, too few frames, an unresolved fault, stage records only. The FTP
fetch and the HDMI capture are not tested here. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# gdi64.exe's window as pw_ms_present shows it: the 800x600 desktop at 560,240 (black), the orange
# 400x300 window at 200,150 of it, the green 200x150 rectangle at 100,75 of the window.
window() { # window OUT PIXFMT
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
        -vf "drawbox=x=760:y=390:w=400:h=300:color=0xff8000:t=fill,drawbox=x=860:y=465:w=200:h=150:color=0x00ff00:t=fill" \
        -frames:v 1 -f rawvideo -pix_fmt "$2" "$1"
}
window "$TMP/win-rgba.raw" rgba
window "$TMP/win-bgra.raw" bgra
ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" -frames:v 1 -f rawvideo -pix_fmt rgba "$TMP/black.raw"
for f in win-rgba win-bgra black; do
    "$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/$f.raw" --out "$TMP/$f.png" >/dev/null 2>&1
done

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

case_ f1 f1-pass.log        0 PASS  "cpu=translator wow_bound=38/38"
case_ f1 f1-unbound.log     1 FAIL  "wow_bound=37/38 not all"
case_ f1 f1-sehfail.log     1 FAIL  "seh=frame:0 != ok"
case_ f2 f1-sehfail.log     0 "PASS (no shot)" "" --no-shot
case_ f1 f1-native.log      1 FAIL  "cpu=none != translator"
case_ f1 f1-unresolved.log  1 FAIL  "faults_unresolved=1 != 0"
case_ f1 f1-stagesonly.log  1 NOLOG "stage records: wow_bind,low_map,display"
case_ f2 f1-stagesonly.log  1 NOLOG "stage records: wow_bind,low_map,display" --no-shot
case_ f2 f1-pass.log        0 "PASS (framebuffer)" "pixel=ff8000 window=ok" --fb --shot "$TMP/win-rgba.png"
case_ f2 f1-pass.log        1 FAIL  "pixel 780,410: rgb=0," --fb --shot "$TMP/win-bgra.png"
case_ f2 f1-pass.log        1 FAIL  "pixel 960,540" --fb --shot "$TMP/black.png"
case_ f2 f1-pass.log        0 PASS  "pixel=ff8000" --shot "$TMP/win-rgba.png"   # an HDMI frame given as a file
case_ f2 f2-nowindow.log    1 FAIL  "window=create:1400 != ok" --no-shot

case_ f  f-pass.log         0 PASS  "cpu=translator frames=17400 fps=58.0"
case_ f  f-native.log       1 FAIL  "cpu=none != translator"
case_ f  f-slow.log         1 FAIL  "frames=540 < 600"
case_ f  f-unresolved.log   1 FAIL  "faults_unresolved=1 != 0"
case_ f  f-stagesonly.log   1 NOLOG "stage records: wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_f_test: $fails failure(s)"; exit 1; fi
echo "check_f_test: all passed"

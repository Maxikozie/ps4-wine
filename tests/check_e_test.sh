#!/usr/bin/env bash
# check_e_test.sh: run scripts/ps4/check.sh e1 against fixture logs and generated framebuffer dumps, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_e_test.sh

Runs scripts/ps4/check.sh e1 on each tests/fixtures/e1-*.log (synthetic: written before the first e1
launch), with --fb on generated 1920x1080 dumps converted by fbshot.sh --raw (the title's Vulkan frame:
cyan with an orange 64x64 square on 240,135, in R,G,B,A and the same bytes read as B,G,R,A) and with
--no-shot, and checks the exit code and the verdict column: a pass, the d1 test pattern instead of the
e1 frame (a stale readback), an import slot not bound, a GPU hang, no device, stage records only
(NOLOG naming the stages). Then e2 and e3 on tests/fixtures/e2-*.log (one vk64.exe launch gives
both lines) with generated dumps of vk64.exe's frame (red, a green square on 240,135): a pass, no
surface (e2 passes, e3 fails), an extension DXVK needs hidden, a winevulkan slot not bound, stage
records only. Then e (milestone e's own rule) on tests/fixtures/e-*.log with generated dumps of
d3d11tri64.exe's frame (a yellow triangle over the centre, blue elsewhere): a pass, a lost device,
Wine's own d3d11 refusing (no DXVK), stage records only. The FTP fetch is not tested here.
Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# frame OUT PIXFMT BACKGROUND SQUARE: a 1920x1080 background with a 64x64 square around 240,135 and a
# 400x400 one around 960,540 (both the background colour for e1), as raw bytes in PIXFMT order, then a PNG.
frame() {
    ffmpeg -loglevel error -y -f lavfi -i "color=c=$3:s=1920x1080" \
        -vf "drawbox=x=208:y=103:w=64:h=64:color=$4:t=fill,drawbox=x=760:y=340:w=400:h=400:color=$5:t=fill" \
        -frames:v 1 -f rawvideo -pix_fmt "$2" "$TMP/frame.raw"
    "$ROOT/scripts/ps4/fbshot.sh" --raw "$TMP/frame.raw" --out "$1" >/dev/null 2>&1
}
frame "$TMP/e1-rgba.png" rgba 0x00ffff 0xff8000 0x00ffff
frame "$TMP/e1-bgra.png" bgra 0x00ffff 0xff8000 0x00ffff
frame "$TMP/d1-pattern.png" rgba black 0xff8000 0x00ff00
frame "$TMP/e3-rgba.png" rgba 0xff0000 0x00ff00 0xff0000
frame "$TMP/e3-bgra.png" bgra 0xff0000 0x00ff00 0xff0000
frame "$TMP/e-rgba.png" rgba 0x0000ff 0x0000ff 0xffff00
frame "$TMP/e-bgra.png" bgra 0x0000ff 0x0000ff 0xffff00

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

case_ e1 e1-pass.log       0 "PASS (framebuffer)" "vk_bound=19/19" --fb --shot "$TMP/e1-rgba.png"
case_ e1 e1-pass.log       1 FAIL  "pixel 240,135: rgb=0," --fb --shot "$TMP/e1-bgra.png"
case_ e1 e1-pass.log       1 FAIL  "pixel 960,540: rgb=0,2" --fb --shot "$TMP/d1-pattern.png"
case_ e1 e1-pass.log       0 "PASS (no shot)" "" --no-shot
case_ e1 e1-unbound.log    1 FAIL  "vk_bound=18/19 not all" --no-shot
case_ e1 e1-hang.log       1 FAIL  "gpu_hang=1 != 0" --fb --shot "$TMP/e1-rgba.png"
case_ e1 e1-nodevice.log   1 FAIL  "inst=fail:vkEnumeratePhysicalDevices:-3:0 != ok" --no-shot
case_ e1 e1-stagesonly.log 1 NOLOG "stage records: vk_load,vk_caps,display,release" --no-shot
case_ e2 e2-pass.log        0 PASS  "wv_bound=15/15"
case_ e3 e2-pass.log        0 "PASS (framebuffer)" "frames=330" --fb --shot "$TMP/e3-rgba.png"
case_ e3 e2-pass.log        1 FAIL  "pixel 960,540: rgb=0," --fb --shot "$TMP/e3-bgra.png"
case_ e3 e2-pass.log        1 FAIL  "pixel 960,540: rgb=0,2" --fb --shot "$TMP/e1-rgba.png"   # e1's frame is not e3's
case_ e2 e2-nosurface.log   0 PASS  "exts_dxvk=ok"
case_ e3 e2-nosurface.log   1 FAIL  "surface=fail:vkCreateWin32SurfaceKHR:-1000000000 != ok" --no-shot
case_ e2 e2-hiddenext.log   1 FAIL  "exts_dxvk=VK_EXT_transform_feedback != ok"
case_ e2 e2-unbound.log     1 FAIL  "wv_bound=14/15 not all"
case_ e2 e2-stagesonly.log  1 NOLOG "stage records: w32u_bind,wv_bind,display"
case_ e3 e2-stagesonly.log  1 NOLOG "stage records: w32u_bind,wv_bind,display" --no-shot
case_ e  e-pass.log          0 "PASS (framebuffer)" "px_c=ffff00" --fb --shot "$TMP/e-rgba.png"
case_ e  e-pass.log          1 FAIL  "pixel 960,540: rgb=0," --fb --shot "$TMP/e-bgra.png"
case_ e  e-pass.log          1 FAIL  "pixel 960,540: rgb=2" --fb --shot "$TMP/e3-rgba.png"   # e3's frame is not e's
case_ e  e-pass.log          0 "PASS (no shot)" "" --no-shot
case_ e  e-hang.log          1 FAIL  "gpu_hang=1 != 0" --no-shot
case_ e  e-nodxvk.log        1 FAIL  "frames=0 < 300" --no-shot
case_ e  e-stagesonly.log    1 NOLOG "stage records: display" --no-shot

if [ "$fails" -ne 0 ]; then echo "check_e_test: $fails failure(s)"; exit 1; fi
echo "check_e_test: all passed"

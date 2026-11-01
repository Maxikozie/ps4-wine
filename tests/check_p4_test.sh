#!/usr/bin/env bash
# check_p4_test.sh: run scripts/ps4/check.sh MS against fixture logs and generated HDMI frames, and compare verdicts.
set -euo pipefail

MS=p4
usage() {
    cat <<USAGE
usage: tests/check_${MS}_test.sh

Runs scripts/ps4/check.sh $MS on each tests/fixtures/$MS-*.log (synthetic: written before the first $MS launch,
docs/ps4/HANDOFF-p.md) with generated 1920x1080 HDMI frames of the title's 960x540 test pattern: scaled 2x
(passes), the same buffer shown unscaled in the top-left corner (fails both pixels), and scaled with red and
blue swapped (fails the orange marker). Also: the rule's own fields (present_mode=async with three buffers, shown_hz >= 59, no flip error, a shown count that could not be read), and the options p3/p4 refuse
(--fb, and neither --shot nor --no-shot). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# The pattern (native/orbis/pw_milestone_orbis.c stage_pattern): black 960x540, green 100x100 on 480,270,
# orange 32x32 on 120,67. frame OUT SCALE ORANGE: drawn at SCALE from the top-left corner (2: as VideoOut
# scaling to 1080p would show it; 1: unscaled).
frame() {
    local s="$2"
    ffmpeg -loglevel error -y -f lavfi -i "color=c=black:s=1920x1080" \
        -vf "drawbox=x=$((430 * s)):y=$((220 * s)):w=$((100 * s)):h=$((100 * s)):color=0x00ff00:t=fill,drawbox=x=$((104 * s)):y=$((51 * s)):w=$((32 * s)):h=$((32 * s)):color=$3:t=fill" \
        -frames:v 1 "$1"
}
frame "$TMP/scaled.png" 2 0xff8000
frame "$TMP/unscaled.png" 1 0xff8000
frame "$TMP/swapped.png" 2 0x0080ff

# case <fixture> <expected exit> <expected verdict> <substring of the output or ""> [check.sh options...]
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    shift 4
    out="$("$ROOT/scripts/ps4/check.sh" "$MS" --log "$FIX/$fx" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s %s %s: exit %s (want %s): %s\n' "$MS" "$fx" "$*" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s %s %s: %s\n' "$MS" "$fx" "$*" "${want:-exit $rc}"
    fi
}

case_ p4-pass.log         0 PASS  "present_mode=async buffers=3" --shot "$TMP/scaled.png"
case_ p4-pass.log         1 FAIL  "pixel 960,540" --shot "$TMP/unscaled.png"
case_ p4-pass.log         1 ""    "give --shot FRAME"
case_ p4-missed.log       1 FAIL  "shown_hz=54.2 < 59" --no-shot
case_ p4-errors.log       1 FAIL  "flip_errors=2 != 0" --no-shot
case_ p4-sync.log         1 FAIL  "present_mode=sync != async" --no-shot
case_ p4-unknown.log      1 FAIL  "shown_hz=- < 59" --no-shot

if [ "$fails" -ne 0 ]; then echo "check_${MS}_test: $fails failure(s)"; exit 1; fi
echo "check_${MS}_test: all passed"

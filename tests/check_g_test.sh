#!/usr/bin/env bash
# check_g_test.sh: run scripts/ps4/check.sh's milestone g rules against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_g_test.sh

Runs scripts/ps4/check.sh g1n, g1m, g1, g2, g and gseg on tests/fixtures/g*.log (synthetic: written before
the first g launch, docs/ps4/HANDOFF-g.md): wow32.exe's checks on the native CPU pass and on the translator
fail; vk32.exe's placed maps pass and a refused one fails; d3d9tri32.exe with batching passes and without
fails; the menu mark passes and a crash before it fails; g passes with the mark, 300 s, 24.7 fps and 1180
crossings a frame, and fails without the mark, at 19.9 fps, at 2400 crossings, or when the game ended 212 s
after the mark; a segment's fields pass; stage records only is NOLOG naming the stages. The pixel rules of
g1m and g1 are the e and f checks' (--no-shot here). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case_ <ms> <fixture> <expected exit> <expected verdict> <substring of the output or ""> [extra args]
case_() {
    local ms="$1" fx="$2" want_rc="$3" want="$4" sub="$5" out rc=0
    shift 5
    out="$("$ROOT/scripts/ps4/check.sh" "$ms" --log "$FIX/$fx" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s %s: exit %s (want %s): %s\n' "$ms" "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s %s: %s\n' "$ms" "$fx" "$want"
    fi
}

case_ g1n  g1n-pass.log          0 PASS  "cpu=native native_caps=7"
case_ g1n  g1n-translator.log    1 FAIL  "cpu=translator != native"
case_ g1m  g1m-pass.log          0 "PASS (no shot)" "map32=ok" --no-shot
case_ g1m  g1m-placedrefused.log 1 FAIL  "map=fail:-5 != ok" --no-shot
case_ g1   g1-pass.log           0 "PASS (no shot)" "batch=1 crossings_per_frame=16" --no-shot
case_ g1   g1-nobatch.log        1 FAIL  "batch=0 != 1" --no-shot
case_ g2   g2-pass.log           0 PASS  "menu=1"
case_ g2   g2-crashed.log        1 FAIL  "menu=0 != 1"
case_ g    g-pass.log            0 PASS  "gameplay=1"
case_ g    g-nomark.log          1 FAIL  "gameplay=0 != 1"
case_ g    g-slow.log            1 FAIL  "fps_avg=19.9 < 20"
case_ g    g-crossings.log       1 FAIL  "crossings_per_frame=2400 > 2000"
case_ g    g-short.log           1 FAIL  "session_s=212 < 300"
case_ gseg gseg-pass.log         0 PASS  "seg=hub"
case_ g    g-stagesonly.log      1 NOLOG "stage records: wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_g_test: $fails failure(s)"; exit 1; fi
echo "check_g_test: all passed"

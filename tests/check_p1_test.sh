#!/usr/bin/env bash
# check_p1_test.sh: run scripts/ps4/check.sh p1 against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_p1_test.sh

Runs scripts/ps4/check.sh p1 on each tests/fixtures/p1-*.log (synthetic: written before the first p1
launch, docs/ps4/HANDOFF-p.md) and checks the exit code and the verdict column: a pass whose klog copy
(cut at 512 bytes) arrives after the whole netlog copy, so the longest copy must be the one read; pad
input during the segment; a histogram with no samples ("-"); Pinball gone before the segment ended; too
few presents for attract mode; an unresolved fault; only the cut klog copy (the histogram fields lost:
a FAIL, not a pass); stage records only (NOLOG naming the stages). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> <substring of the line or "">
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" p1 --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL p1 %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   p1 %s: %s\n' "$fx" "${want:-exit $rc}"
    fi
}

case_ p1-pass.log        0 PASS  "flip_us_max=17900 frame_us_avg=18380"
case_ p1-input.log       1 FAIL  "inputs=3 != 0"
case_ p1-nohist.log      1 FAIL  "keep_us_min=- not a number"
case_ p1-early.log       1 FAIL  "end=- != segment"
case_ p1-few.log         1 FAIL  "presents=420 < 600"
case_ p1-unresolved.log  1 FAIL  "faults_unresolved=1 != 0"
case_ p1-trunc.log       1 FAIL  "flip_us_min=missing not a number"
case_ p1-stagesonly.log  1 NOLOG "stage records: wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_p1_test: $fails failure(s)"; exit 1; fi
echo "check_p1_test: all passed"

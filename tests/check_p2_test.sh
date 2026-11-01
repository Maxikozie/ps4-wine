#!/usr/bin/env bash
# check_p2_test.sh: run scripts/ps4/check.sh p2 against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_p2_test.sh

Runs scripts/ps4/check.sh p2 on each tests/fixtures/p2-*.log (synthetic: written before the first p2 launch,
docs/ps4/HANDOFF-p.md) and checks the exit code and the verdict column. p2 is correctness only: a pass on
the native CPU with native_caps=7; the segment on the translator (no Orbis native backend: native_caps=-);
the title's probe finding no alternate stack (native_caps=0); an unresolved fault; the segment cut short;
pad input; stage records only (NOLOG naming the stages). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> <substring of the line or "">
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" p2 --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL p2 %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   p2 %s: %s\n' "$fx" "${want:-exit $rc}"
    fi
}

case_ p2-pass.log         0 PASS  "native_caps=7 cpu=native"
case_ p2-translator.log   1 FAIL  "native_caps=- != 7"
case_ p2-noaltstack.log   1 FAIL  "native_caps=0 != 7"
case_ p2-unresolved.log   1 FAIL  "faults_unresolved=2 != 0"
case_ p2-early.log        1 FAIL  "end=- != segment"
case_ p2-input.log        1 FAIL  "inputs=4 != 0"
case_ p2-stagesonly.log   1 NOLOG "stage records: wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_p2_test: $fails failure(s)"; exit 1; fi
echo "check_p2_test: all passed"

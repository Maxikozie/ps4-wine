#!/usr/bin/env bash
# check_p5w_test.sh: run scripts/ps4/check.sh p5w against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_p5w_test.sh

Runs scripts/ps4/check.sh p5w on each tests/fixtures/p5w-*.log (synthetic: written before the first p5w
launch, docs/ps4/HANDOFF-p.md): every window made on every thread passes; the PS4's failure before patch
1100 (no window and no CBT hook on a new thread) fails naming new_ok and cbt_new; a program that never
reported fails on exit and its counts; stage records only is NOLOG naming the stages. Exit 0 when every
case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> <substring of the output or "">
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" p5w --log "$FIX/$fx" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL p5w %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   p5w %s: %s\n' "$fx" "$want"
    fi
}

case_ p5w-pass.log       0 PASS  "hold_flex_kib=768"
case_ p5w-callbacks.log  1 FAIL  "new_ok=0/14 not all cbt_new=0 < 1"
case_ p5w-timeout.log    1 FAIL  "exit=timeout != 0"
case_ p5w-stagesonly.log 1 NOLOG "stage records: wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_p5w_test: $fails failure(s)"; exit 1; fi
echo "check_p5w_test: all passed"

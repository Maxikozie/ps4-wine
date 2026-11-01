#!/usr/bin/env bash
# check_p6_test.sh: run scripts/ps4/check.sh p6 against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_p6_test.sh

Runs scripts/ps4/check.sh p6 on each tests/fixtures/p6-*.log (synthetic: written before the first p6
launch, docs/ps4/HANDOFF-p.md): Wine's threads on their own stacks (keep, 64 KiB for 8) pass; the old
floor (98304 KiB for 8) fails naming hold_flex_kib; a keep that libkernel refused and the layer's 512 KiB
fallback took (4608 KiB for 8) passes with the refusals in the line; a kept stack that broke the window
callbacks fails on p5w's part of the rule; stage records only is NOLOG naming the stages. Exit 0 when
every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> <substring of the output or "">
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" p6 --log "$FIX/$fx" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL p6 %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   p6 %s: %s\n' "$fx" "$want"
    fi
}

case_ p6-pass.log       0 PASS  "stack_policy=keep hold_flex_kib=64"
case_ p6-floor.log      1 FAIL  "hold_flex_kib=98304 > 8192"
case_ p6-refused.log    0 PASS  "threads_keep_refused=33"
case_ p6-callbacks.log  1 FAIL  "new_ok=0/14 not all cbt_new=0 < 1"
case_ p6-stagesonly.log 1 NOLOG "stage records: stack_probe,wow_bind,display"

if [ "$fails" -ne 0 ]; then echo "check_p6_test: $fails failure(s)"; exit 1; fi
echo "check_p6_test: all passed"

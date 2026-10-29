#!/usr/bin/env bash
# check_a_test.sh: run scripts/ps4/check.sh a against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_a_test.sh

Runs scripts/ps4/check.sh a --no-shot on each tests/fixtures/a-*.log and checks the exit code
and the verdict column. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> [<substring of the line>]
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="${4:-}" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" a --no-shot --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s: %s\n' "$fx" "$want"
    fi
}

case_ a-pass.log  0 PASS  "loadexec=ok"          # the last PS4WINE a line wins; klog/netlog prefixes stripped
case_ a-768.log   1 FAIL  "direct_mib=768 < 4000"
case_ a-nojit.log 1 FAIL  "jit=err:0x8002000d != ok"
case_ a-dmemcrash.log 1 FAIL "direct_mib=crash < 4000"   # a crashed gated stage is never a pass
case_ a-jitcrash.log  1 FAIL "jit=crash != ok"
case_ a-nolog.log 1 NOLOG
case_ a-crash.log 1 CRASH "signal 11 in stage dmem"

if [ "$fails" -ne 0 ]; then echo "check_a_test: $fails failure(s)"; exit 1; fi
echo "check_a_test: all passed"

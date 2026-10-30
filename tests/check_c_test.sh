#!/usr/bin/env bash
# check_c_test.sh: run scripts/ps4/check.sh c against fixture logs and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_c_test.sh

Runs scripts/ps4/check.sh c on each tests/fixtures/c-*.log and checks the exit code, the verdict
column and, where given, a substring of the line. The fixtures are the title's records as logs.sh
writes them (klog with the Syscore tag, netlog raw). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <fixture> <expected exit> <expected verdict> [<substring of the line>]
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="${4:-}" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" c --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s: %s\n' "$fx" "$want"
    fi
}

case_ c-pass.log     0 PASS  'stdout="Hello from PE64" server=inprocess exit=0'   # klog and netlog copies; the last wins
case_ c-nostdout.log 1 FAIL  "stdout mismatch"                                    # exit 0 but nothing reached fd 1
case_ c-exit1.log    1 FAIL  "exit=1 != 0"                                        # the program (or Wine) ended with 1
case_ c-abort.log    1 FAIL  "exit=abort != 0"                                    # a shim or the server called abort()
case_ c-noserver.log 1 FAIL  "server=none != inprocess"                           # STDOUT arrived without the server mark
case_ c-timeout.log  1 FAIL  "exit=timeout != 0"                                  # the watchdog reported, Wine never left
case_ c-crash.log    1 CRASH "fault signal=11"                          # the early fault report, no check line
case_ c-nolog.log    1 NOLOG

if [ "$fails" -ne 0 ]; then echo "check_c_test: $fails failure(s)"; exit 1; fi
echo "check_c_test: all passed"

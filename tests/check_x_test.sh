#!/usr/bin/env bash
# check_x_test.sh: run scripts/ps4/check.sh x1 against fixture logs and compare verdicts
# (docs/ps4/HANDOFF-loop.md, phase 1; x2 and x3 join when their rules are written).
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_x_test.sh

Runs scripts/ps4/check.sh x1 on each tests/fixtures/x1-*.log case and checks the exit code and the
verdict column. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <milestone> <fixture> <expected exit> <expected verdict> [<substring of the output>]
case_() {
    local ms="$1" fx="$2" want_rc="$3" want="$4" sub="${5:-}" out rc=0
    out="$("$ROOT/scripts/ps4/check.sh" "$ms" --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s: %s\n' "$fx" "$want"
    fi
}

case_ x1 x1-pass.log         0 PASS   "dialog_by=eye shot=20261104-120140-x1.png"
case_ x1 x1-judged-last.log  0 PASS   "dialog=0"
case_ x1 x1-unjudged.log     1 FAIL   "dialog=unjudged != 0"
case_ x1 x1-dialog.log       1 FAIL   "dialog=1 != 0"
case_ x1 x1-nokill.log       1 FAIL   "kill=refused != ok"
case_ x1 x1-noinstall.log    1 FAIL   "install=fail != ok"
case_ x1 x1-oldstamp.log     1 FAIL   "stamp_match=0 != 1"
case_ x1 x1-nohello.log      1 FAIL   "hello=none != ok kill=none != ok install=none != ok launch=none != ok stamp_match=0 != 1"
case_ x1 x1-nolog.log        1 NOLOG  "no 'PS4WINE x1' line"
# A live title's handled Wine error is not the ctl's crash (x1 run 1 was printed as CRASH on one).
case_ x1 x1-wineerr.log      1 NOLOG  "no 'PS4WINE x1' line"
case_ x1 x1-ctlcrash.log     1 CRASH  "crash dump: ScePartyDaemon: page fault (user read instruction, page not present)"

if [ "$fails" -ne 0 ]; then echo "check_x_test: $fails failure(s)"; exit 1; fi
echo "check_x_test: all passed"

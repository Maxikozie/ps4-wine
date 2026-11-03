#!/usr/bin/env bash
# check_l_test.sh: run scripts/ps4/check.sh i1 against fixture logs and compare verdicts
# (docs/ps4/HANDOFF-i.md; milestone i's own cases join when its rule is written).
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_l_test.sh

Runs scripts/ps4/check.sh l1 on each tests/fixtures/l1-*.log case and checks the exit code and the
verdict column. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <milestone> <fixture> <expected exit> <expected verdict> [<substring of the output>]
LOG_MD="$FIX/no-such-LOG.md"
case_() {
    local ms="$1" fx="$2" want_rc="$3" want="$4" sub="${5:-}" out rc=0
    out="$(CHECK_LOG_MD="$LOG_MD" "$ROOT/scripts/ps4/check.sh" "$ms" --log "$FIX/$fx" 2>/dev/null)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s: exit %s (want %s): %s\n' "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s: %s\n' "$fx" "$want"
    fi
}

case_ l1 l1-pass.log          0 PASS  "buttons_seen=0xf3ff"
case_ l1 l1-nobutton.log      1 FAIL  "buttons_seen=0xf3df != 0xf3ff"
case_ l1 l1-notconnected.log  1 FAIL  "get0=1167 != 0"
case_ l1 l1-shortstick.log    1 FAIL  "ry_min=-29000 > -30000"
case_ l1 l1-norumble.log      1 FAIL  "rumble_events=0 < 2"

if [ "$fails" -ne 0 ]; then echo "check_l_test: $fails failure(s)"; exit 1; fi
echo "check_l_test: all passed"

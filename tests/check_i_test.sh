#!/usr/bin/env bash
# check_i_test.sh: run scripts/ps4/check.sh i1 against fixture logs and compare verdicts
# (docs/ps4/HANDOFF-i.md; milestone i's own cases join when its rule is written).
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_i_test.sh

Runs scripts/ps4/check.sh i1 on each tests/fixtures/i1-*.log case and check.sh i on the i-*.log cases
(with CHECK_LOG_MD pointing at a fixture LOG.md) and checks the exit code and the verdict column. Exit 0
when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
fails=0

# case <milestone> <fixture> <expected exit> <expected verdict> [<substring of the output>]
# (LOG_MD: the LOG.md check.sh i reads)
LOG_MD="$FIX/i-LOG.md"
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

case_ i1 i1-pass.log        0 PASS  "low_end=0x4fc000"            # the whole netlog line; the klog copy is the same
case_ i1 i1-homedeath.log   0 PASS  "launches=1"                  # Home and back after the line is recorded only
case_ i1 i1-release.log     1 FAIL  "release=err:0x80020016 != ok"
case_ i1 i1-reserve.log     1 FAIL  "reserve400=err:0x8002000c != ok"
case_ i1 i1-short.log       1 FAIL  "alive_s=590 < 600"
case_ i1 i1-unwindfault.log 1 FAIL  "faults_unresolved=1 != 0"    # a recorded field's fault still counts
case_ i1 i1-stagesonly.log  1 CRASH "stage records: direct,vo1,release,reserve400,exec400"

case_ i i-pass.log          0 PASS  "eboot_release=ok low_end=0x410000"
case_ i i-relocated.log     1 FAIL  "base=0x00110000 != 0x00400000"
case_ i i-c0000018.log      1 FAIL  "base=- != 0x00400000"
case_ i i-off.log           1 FAIL  "eboot_release=off != ok"
LOG_MD="$FIX/i-LOG-nog2.md"
case_ i i-pass.log          1 FAIL  "LOG.md has no g2 PASS of build abc1234 with eboot_release=ok"
LOG_MD="$FIX/i-LOG-g1off.md"
case_ i i-pass.log          1 FAIL  "LOG.md has no g1 PASS of build abc1234 with eboot_release=ok"
LOG_MD="$FIX/no-such-LOG.md"
case_ i i-pass.log          1 FAIL  "LOG.md has no g1n PASS"

if [ "$fails" -ne 0 ]; then echo "check_i_test: $fails failure(s)"; exit 1; fi
echo "check_i_test: all passed"

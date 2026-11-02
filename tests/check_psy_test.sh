#!/usr/bin/env bash
# check_psy_test.sh: run scripts/ps4/check.sh's Psychonauts rules (j, later k-n) against fixture logs.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_psy_test.sh

Runs scripts/ps4/check.sh j on tests/fixtures/j-*.log (synthetic: written 2026-11-02 before the first j run,
docs/ps4/HANDOFF-i.md). j is the host's line from host-game.sh --game psychonauts: it passes ("PASS (host)")
with the EXE at 0x00400000, no missing DLL, 41200 presents, a new save, the pad read and 725 s; it fails with
the EXE moved to 0x00410000, with a missing DLL, with 3100 presents, after 431 s, without a new save and
without a pad read; a log whose game crashed before host-game.sh wrote the line is CRASH. host-game.sh --parse
reads the fields from Wine's output: with every game DLL loaded and only Wine's Indeo codec missing
winegstreamer, dll_missing=0 and dll_missing_wine=1 (the user's choice, 2026-11-02, after the smoke run); a
missing import of the EXE and of binkw32 plus OpenAL32 never loaded is dll_missing=3. The fixtures for
k, l, m and n join these before their first launches.
Exit 0 when every case matches.
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

case_ j j-pass.log         0 "PASS (host)" "pad_reads=40890"
case_ j j-base-moved.log   1 FAIL  "exe_base=0x00410000 != 0x00400000"
case_ j j-dll-missing.log  1 FAIL  "dll_missing=1 != 0"
case_ j j-fewpresents.log  1 FAIL  "presents=3100 < 3600"
case_ j j-short.log        1 FAIL  "session_s=431 < 600"
case_ j j-nosave.log       1 FAIL  "save_new=0 != 1"
case_ j j-nopad.log        1 FAIL  "pad_reads=0 < 1"
case_ j j-crash.log        1 CRASH "Unhandled page fault"

# parse_ <fixture> <session seconds> <expected output of host-game.sh --parse>
parse_() {
    local fx="$1" secs="$2" want="$3" out rc=0
    out="$("$ROOT/scripts/ps4/host-game.sh" --game psychonauts --parse "$FIX/$fx" --session-s "$secs" 2>&1)" || rc=$?
    if [ "$rc" != 0 ] || [ "$out" != "$want" ]; then
        printf 'FAIL parse %s: exit %s\n  got  %s\n  want %s\n' "$fx" "$rc" "$out" "$want"
        fails=$((fails + 1))
    else
        printf 'ok   parse %s\n' "$fx"
    fi
}

parse_ j-parse-codec.log 600 "exe_base=0x00400000 dll_missing=0 dll_missing_wine=1 dll_absent=- presents=3601 fps_avg=6.0 crossings_per_frame=25 pad_reads=38 pad_calls=40 pad_first_read_ms=232 rumble_events=2 rumble=ok marks=1 dxvk_conf=found steam_init=-"
parse_ j-parse-gamemiss.log 0 "exe_base=0x00410000 dll_missing=3 dll_missing_wine=0 dll_absent=binkw32,openal32 presents=1 fps_avg=- crossings_per_frame=- pad_reads=- pad_calls=- pad_first_read_ms=- rumble_events=- rumble=- marks=- dxvk_conf=- steam_init=-"

if [ "$fails" -eq 0 ]; then echo "check_psy_test: all passed"; else echo "check_psy_test: $fails failure(s)"; exit 1; fi

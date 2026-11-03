#!/usr/bin/env bash
# psy_bindings_test.sh: scripts/ps4/psy-bindings.sh on synthetic profile INIs (milestone l's restart check).
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/psy_bindings_test.sh

Writes synthetic Psychonauts profile INIs (a [Global] section of options and an [Input] section with the
Defaults' pad column) and checks scripts/ps4/psy-bindings.sh: the Defaults pass the one-file check, a pad
column holding a keyboard name (Jump_Alt=P, Wine bug 20834) fails it; two files that differ only in an option
and in CR line ends are the same, a changed binding is a difference; a missing file is exit 2, a file without
[Input] exit 1. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/ps4/psy-bindings.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

ini() { # ini FILE RUMBLE JUMP_ALT
    cat >"$1" <<INI
[Global]
InvertCamVert=true
EnableRumble=$2
MouseSensitivity=0.709865

[Input]
MoveForward=W
Jump=Spacebar
Journal=Escape
MoveForward_Alt=Up
MoveBackward_Alt=Down
MoveLeft_Alt=Left
MoveRight_Alt=Right
Jump_Alt=$3
Attack_Alt=Joy1
Use_Alt=Joy4
Cancel_Alt=Joy3
LockOn/Float_Alt=Joy5
PsiPower1_Alt=Joy6
PsiPower2_Alt=Joy7
PsiPower3_Alt=Joy8
InventoryMenu_Alt=DPadLeft
PsiPowersMenu_Alt=DPadRight
FirstPerson_Alt=Joy12
Journal_Alt=Joy9
Stats_Alt=Joy11
LookUp_Alt=JoyRotZ
LookDown_Alt=JoyRotZ
LookLeft_Alt=JoyZ
LookRight_Alt=JoyZ
INI
}
ini "$TMP/defaults.ini" true Joy2
ini "$TMP/mangled.ini" true P
ini "$TMP/options.ini" false Joy2
sed -i 's/$/\r/' "$TMP/options.ini"
printf '[Global]\nEnableRumble=true\n' >"$TMP/noinput.ini"

case_() { # case_ NAME WANT_RC SUBSTRING ARGS...
    local name="$1" want="$2" sub="$3" out rc=0
    shift 3
    out="$("$SCRIPT" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want" ] || [[ "$out" != *"$sub"* ]]; then
        printf 'FAIL %s: exit %s (want %s): %s\n' "$name" "$rc" "$want" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s\n' "$name"
    fi
}

case_ defaults         0 "the pad column is the Defaults (21 entries)" "$TMP/defaults.ini"
case_ mangled          1 "+Jump_Alt=P"                                 "$TMP/mangled.ini"
case_ options-and-crlf 0 "the same 24 binding lines"                   "$TMP/defaults.ini" "$TMP/options.ini"
case_ changed-binding  1 "+Jump_Alt=P"                                 "$TMP/defaults.ini" "$TMP/mangled.ini"
case_ missing          2 "no such file"                                "$TMP/defaults.ini" "$TMP/none.ini"
case_ no-input         1 "no [Input] lines"                            "$TMP/noinput.ini"

if [ "$fails" -ne 0 ]; then echo "psy_bindings_test: $fails failure(s)"; exit 1; fi
echo "psy_bindings_test: all passed"

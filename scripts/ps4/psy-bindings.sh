#!/usr/bin/env bash
# psy-bindings.sh: Psychonauts' bindings from a profile INI (milestone l, docs/ps4/HANDOFF-i.md): the restart
# check compares the binding lines only, so a rewritten option elsewhere in the file is no failure.
set -euo pipefail

usage() {
    cat <<USAGE
usage: scripts/ps4/psy-bindings.sh FILE
       scripts/ps4/psy-bindings.sh BEFORE AFTER

FILE is a Psychonauts profile INI ("Profile 1- <name>.ini", from game.sh --game psychonauts --saves-pull).
The binding lines are the [Input] section's key=value lines: the keyboard column and the pad column (*_Alt).
CR line ends are ignored; every other section (the options) is ignored.

One file: prints its binding lines, sorted, then checks the pad column against the game's Defaults
(Options, Bindings, Defaults; measured on the laptop in milestone j, session C, under fork Wine patch 0904):
the pad column of a profile mangled by Wine bug 20834 holds keyboard names (Jump_Alt=P). Exit 0 when every
*_Alt entry equals its default, 1 otherwise (the differences listed).

Two files: prints the differences between their binding lines (diff -u). Exit 0 when they are the same,
1 when they differ.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] && [ $# -le 2 ] || { usage; exit 1; }

# The pad column after Defaults (build/host-game/psychonauts-ini/after-C.ini, 2026-11-03).
DEFAULTS='Attack_Alt=Joy1
Cancel_Alt=Joy3
FirstPerson_Alt=Joy12
InventoryMenu_Alt=DPadLeft
Journal_Alt=Joy9
Jump_Alt=Joy2
LockOn/Float_Alt=Joy5
LookDown_Alt=JoyRotZ
LookLeft_Alt=JoyZ
LookRight_Alt=JoyZ
LookUp_Alt=JoyRotZ
MoveBackward_Alt=Down
MoveForward_Alt=Up
MoveLeft_Alt=Left
MoveRight_Alt=Right
PsiPower1_Alt=Joy6
PsiPower2_Alt=Joy7
PsiPower3_Alt=Joy8
PsiPowersMenu_Alt=DPadRight
Stats_Alt=Joy11
Use_Alt=Joy4'

# bindings FILE: the [Input] section's key=value lines, sorted (LC_ALL=C).
bindings() {
    [ -f "$1" ] || { printf 'psy-bindings: no such file: %s\n' "$1" >&2; exit 2; }
    tr -d '\r' <"$1" | awk '
        /^\[/ { section = tolower($0); next }
        section == "[input]" && /=/ { print }' | LC_ALL=C sort
}

if [ $# -eq 2 ]; then
    a="$(bindings "$1")"
    b="$(bindings "$2")"
    [ -n "$a" ] || { printf 'psy-bindings: no [Input] lines in %s\n' "$1" >&2; exit 1; }
    if [ "$a" = "$b" ]; then
        printf 'psy-bindings: the same %d binding lines\n' "$(printf '%s\n' "$a" | wc -l)"
        exit 0
    fi
    diff -u --label "$1" --label "$2" <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true
    exit 1
fi

lines="$(bindings "$1")"
[ -n "$lines" ] || { printf 'psy-bindings: no [Input] lines in %s\n' "$1" >&2; exit 1; }
printf '%s\n' "$lines"
pad="$(printf '%s\n' "$lines" | grep -E '^[^=]+_Alt=' || true)"
if [ "$pad" = "$DEFAULTS" ]; then
    printf 'psy-bindings: the pad column is the Defaults (%d entries)\n' "$(printf '%s\n' "$pad" | wc -l)"
    exit 0
fi
printf 'psy-bindings: the pad column differs from the Defaults:\n'
diff -u --label defaults --label "$1" <(printf '%s\n' "$DEFAULTS") <(printf '%s\n' "$pad") || true
exit 1

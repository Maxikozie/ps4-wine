#!/usr/bin/env bash
# profile_parse_test.sh: parse every profiles/*.ini and profiles/input/*.input with the fork's own parsers, as
# the PS4 title reads them (milestone k, docs/ps4/HANDOFF-i.md), so a profile that the title would refuse never
# reaches the console. SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/profile_parse_test.sh

Builds tests/profile_parse.c with host clang against the fork's src/pw_app_profile.c, src/pw_game_profile.c,
src/pw_wine_launch.c and src/pw_result.c (third_party/prospero-win) into a temporary directory, then:
  - parses each profiles/*.ini as the title's load_profile does, and checks that its [input] preset, when
    named, is a file under profiles/input/;
  - parses each profiles/input/*.input as the title's g_bindings does;
  - checks psychonauts.ini's fields (saves = C:\\Psychonauts\\Profiles, DXVK_CONFIG_FILE in [debug] env, no
    winedebug line, ...);
  - checks that a profile with a relative saves path is refused (the parser is live, not vacuous).
One OK/FAIL line per file. Exit 0 when every check passes. CC overrides the compiler (default clang, with
/usr/lib/llvm-18/bin first on PATH).
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORK="$ROOT/third_party/prospero-win"
PROFILES="$ROOT/profiles"
[ -d /usr/lib/llvm-18/bin ] && PATH="/usr/lib/llvm-18/bin:$PATH"
CC="${CC:-clang}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$CC" -O1 -std=c11 -Wall -Wextra -Werror -I"$FORK/src" -I"$FORK/include" \
    "$ROOT/tests/profile_parse.c" "$FORK/src/pw_app_profile.c" "$FORK/src/pw_game_profile.c" \
    "$FORK/src/pw_wine_launch.c" "$FORK/src/pw_result.c" -o "$work/profile_parse"

fails=0
fail() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

# field <output> <key>: the value of the first "key=..." line
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1; }

shopt -s nullglob
inis=("$PROFILES"/*.ini)
inputs=("$PROFILES"/input/*.input)
[ "${#inis[@]}" -gt 0 ] || fail "no profiles/*.ini"
[ "${#inputs[@]}" -gt 0 ] || fail "no profiles/input/*.input"

for f in "${inis[@]}"; do
    rel="${f#"$ROOT"/}"
    rc=0
    out="$("$work/profile_parse" ini "$f")" || rc=$?
    if [ "$rc" != 0 ]; then
        fail "$rel: ${out#FAIL "$f": }"
        continue
    fi
    preset="$(field "$out" preset)"
    if [ -n "$preset" ] && [ ! -f "$PROFILES/input/$preset.input" ]; then
        fail "$rel: preset $preset has no profiles/input/$preset.input (the title would use its built-in keys)"
        continue
    fi
    if [ "$(basename "$f")" = psychonauts.ini ]; then
        bad=""
        want() { [ "$(field "$out" "$1")" = "$2" ] || bad+=" $1=$(field "$out" "$1") (want $2)"; }
        want id psychonauts
        want executable 'C:\Psychonauts\Psychonauts.exe'
        want working_directory 'C:\Psychonauts'
        want argc 0
        want dll_overrides 'd3d9=n'
        want architecture pe32
        want desktop 1920x1080
        want preset psychonauts
        want winedebug ''
        want cpu_native 1
        want saves 'C:\Psychonauts\Profiles'
        printf '%s\n' "$out" | grep -qx 'env=DXVK_CONFIG_FILE=C:/Psychonauts/dxvk.conf' ||
            bad+=" env lacks DXVK_CONFIG_FILE=C:/Psychonauts/dxvk.conf"
        printf '%s\n' "$out" | grep -qx 'env=DXVK_HUD=fps,frametimes' || bad+=" env lacks DXVK_HUD=fps,frametimes"
        if [ -n "$bad" ]; then
            fail "$rel:$bad"
            continue
        fi
    fi
    printf 'OK   %s\n' "$rel"
done

for f in "${inputs[@]}"; do
    rel="${f#"$ROOT"/}"
    rc=0
    out="$("$work/profile_parse" input "$f")" || rc=$?
    if [ "$rc" != 0 ]; then
        fail "$rel: ${out#FAIL "$f": }"
        continue
    fi
    printf 'OK   %s (%s)\n' "$rel" "$(field "$out" mode)"
done

# The parser refuses what the title would refuse: a relative saves path.
sed 's/^saves = .*/saves = Profiles/' "$PROFILES/psychonauts.ini" >"$work/relative-saves.ini"
if grep -qx 'saves = Profiles' "$work/relative-saves.ini" &&
    ! "$work/profile_parse" ini "$work/relative-saves.ini" >/dev/null; then
    printf 'OK   a relative saves path is refused\n'
else
    fail "a relative saves path was not refused"
fi

if [ "$fails" -gt 0 ]; then
    printf 'profile_parse_test: %d failed\n' "$fails"
    exit 1
fi
printf 'profile_parse_test: all %d profiles and %d input presets parse as the title reads them\n' \
    "${#inis[@]}" "${#inputs[@]}"

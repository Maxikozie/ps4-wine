#!/usr/bin/env bash
# game_sh_test.sh: scripts/ps4/game.sh's uploads, run for real through lftp's file:// against a fake repo.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/game_sh_test.sh

Copies scripts/ps4/game.sh and common.sh into a fake repo under a mktemp dir (small fake game trees, profiles,
presets; games/ of the real repo is never read) and uploads with PS4_GAME_OPEN="open file:///;" into a fake
console directory (PS4_DATA_ROOT). Checks, for --game psychonauts: the profile and the preset arrive; the game
arrives without WorkResource/Sounds/French/ and German/ (a name with a space included); the support INIs and
psychonauts.dxvk.conf arrive in the game folder under their names (dxvk.conf); the manifest has one line per
file with the dxvk.conf's sha256; a second run sends nothing (an old remote mtime stays); a truncated remote
file is sent again whole; a deleted remote file fails --verify-only; saves push and pull Profiles/ with a space
in the path. For --game vtmb (the default): the excluded files (__redist/, Loader.exe, goggame-*) stay off the
console. An unknown game is refused. Needs lftp and python3. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v lftp > /dev/null || { echo "game_sh_test: lftp missing" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1" >&2; FAILS=$((FAILS + 1)); }
expect() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# The fake repo.
R="$T/repo"
mkdir -p "$R/scripts/ps4" "$R/profiles/input"
command cp -f "$REPO/scripts/ps4/game.sh" "$REPO/scripts/ps4/common.sh" "$R/scripts/ps4/"
G="$R/games/psychonauts/game"
mkdir -p "$G/WorkResource/Sounds/French" "$G/WorkResource/Sounds/German" "$G/WorkResource/cutscenes" \
    "$G/Documents" "$R/games/psychonauts/support/app"
printf 'MZ fake exe\n' > "$G/Psychonauts.exe"
head -c 70000 /dev/zero > "$G/WorkResource/Sounds/thvoice.isb"
printf 'fr\n' > "$G/WorkResource/Sounds/French/thvoice.isb"
printf 'de\n' > "$G/WorkResource/Sounds/German/thvoice.isb"
head -c 5000 /dev/urandom > "$G/WorkResource/cutscenes/INTRO.bik"
printf 'manual\n' > "$G/Psychonauts Manual Win.pdf"
printf 'doc\n' > "$G/Documents/a b.txt"
printf '[DisplaySettings]\r\nScreenWidth=1920\r\n' > "$R/games/psychonauts/support/app/DisplaySettings.ini"
printf '[AudioSettings]\r\n' > "$R/games/psychonauts/support/app/AudioSettings.ini"
printf 'language english' > "$R/games/psychonauts/support/app/Psychonauts.ini"
printf 'd3d9.maxFrameRate = 60\n' > "$R/profiles/psychonauts.dxvk.conf"
printf '[application]\nid = psychonauts\n' > "$R/profiles/psychonauts.ini"
printf '[input]\nmode = keyboard\n' > "$R/profiles/input/psychonauts.input"
V="$R/games/bloodlines-up"
mkdir -p "$V/Bin" "$V/__redist"
printf 'MZ\n' > "$V/Vampire.exe"; printf 'MZ\n' > "$V/Loader.exe"; printf 'x\n' > "$V/__redist/vc.exe"
printf 'b\n' > "$V/Bin/engine.dll"; printf 'g\n' > "$V/goggame-1.info"
printf '[application]\nid = vtmb\n' > "$R/profiles/vtmb.ini"
printf '[input]\n' > "$R/profiles/input/vtmb.input"

C="$T/console"
mkdir -p "$C"
export PS4_DATA_ROOT="$C" PS4_GAME_OPEN="open file:///;" BUILD_DIR="$T/build"
mkdir -p "$BUILD_DIR"
GS="$R/scripts/ps4/game.sh"
D="$C/prefix/drive_c/Psychonauts"
run() { "$GS" "$@" > "$T/out" 2>&1; }

expect "psychonauts: first upload exits 0" 'run --game psychonauts'
expect "profile and preset arrive" '[ -f "$C/profiles/psychonauts.ini" ] && [ -f "$C/input/psychonauts.input" ]'
expect "game files arrive (space in a name)" \
    'cmp -s "$G/WorkResource/cutscenes/INTRO.bik" "$D/WorkResource/cutscenes/INTRO.bik" && [ -f "$D/Documents/a b.txt" ] && [ -f "$D/Psychonauts Manual Win.pdf" ]'
expect "French and German are not sent" '[ ! -e "$D/WorkResource/Sounds/French" ] && [ ! -e "$D/WorkResource/Sounds/German" ] && [ -f "$D/WorkResource/Sounds/thvoice.isb" ]'
expect "support INIs in the game folder" 'cmp -s "$R/games/psychonauts/support/app/DisplaySettings.ini" "$D/DisplaySettings.ini" && [ -f "$D/AudioSettings.ini" ] && [ -f "$D/Psychonauts.ini" ]'
expect "dxvk.conf in the game folder" 'cmp -s "$R/profiles/psychonauts.dxvk.conf" "$D/dxvk.conf"'
M="$BUILD_DIR/game-psychonauts.manifest"
expect "manifest: one line per file (9)" '[ "$(wc -l < "$M")" = 9 ]'
expect "manifest: dxvk.conf hashed from its source" \
    'grep -qxF "$(stat -c %s "$R/profiles/psychonauts.dxvk.conf") $(sha256sum "$R/profiles/psychonauts.dxvk.conf" | cut -d" " -f1) dxvk.conf" "$M"'
expect "manifest: no French line" '! grep -q French "$M"'

touch -d 2001-01-01 "$D/WorkResource/cutscenes/INTRO.bik"
expect "second run exits 0" 'run --game psychonauts'
expect "second run sends nothing (old mtime kept)" '[ "$(stat -c %Y "$D/WorkResource/cutscenes/INTRO.bik")" = "$(date -d 2001-01-01 +%s)" ]'

truncate -s 100 "$D/WorkResource/cutscenes/INTRO.bik"; touch -d "+1 hour" "$D/WorkResource/cutscenes/INTRO.bik" # a partly sent file is newer than the source
expect "truncated file: run exits 0" 'run --game psychonauts || { cat "$T/out" >&2; false; }'
expect "truncated file is sent again whole" 'cmp -s "$G/WorkResource/cutscenes/INTRO.bik" "$D/WorkResource/cutscenes/INTRO.bik"'

rm "$D/WorkResource/Sounds/thvoice.isb"
expect "deleted file: --verify-only fails" '! run --game psychonauts --verify-only'
expect "deleted file: named in the output" 'grep -q "missing or wrong size: 70000 WorkResource/Sounds/thvoice.isb" "$T/out"'
rm "$D/dxvk.conf"
expect "deleted extra: --verify-only fails" '! run --game psychonauts --verify-only && grep -q "missing or wrong size: .* dxvk.conf" "$T/out"'
expect "rerun repairs both, --verify-only passes" 'run --game psychonauts && run --game psychonauts --verify-only'

P="$T/saves/Profiles"
mkdir -p "$P/Profile 1"
head -c 61440 /dev/urandom > "$P/Profile 1/SavedGame0"; printf 'Jump_Alt=Joy2\r\n' > "$P/Profile 1/Profile 1- Raz.ini"
expect "saves push exits 0" 'run --game psychonauts --saves-push "$P"'
expect "saves arrive under Profiles/" 'cmp -s "$P/Profile 1/SavedGame0" "$D/Profiles/Profile 1/SavedGame0" && [ -f "$D/Profiles/Profile 1/Profile 1- Raz.ini" ]'
expect "saves pull exits 0" 'run --game psychonauts --saves-pull'
expect "saves come back" 'cmp -s "$P/Profile 1/SavedGame0" "$BUILD_DIR/saves/psychonauts-console/Profile 1/SavedGame0"'

DV="$C/prefix/drive_c/VTMB"
expect "vtmb (default): upload exits 0" 'run'
expect "vtmb: game files arrive" '[ -f "$DV/Vampire.exe" ] && [ -f "$DV/Bin/engine.dll" ] && [ -f "$C/profiles/vtmb.ini" ]'
expect "vtmb: excluded files stay off" '[ ! -e "$DV/Loader.exe" ] && [ ! -e "$DV/__redist" ] && [ ! -e "$DV/goggame-1.info" ]'
expect "vtmb: no extras, manifest of 2 files" '[ "$(wc -l < "$BUILD_DIR/game-vtmb.manifest")" = 2 ]'
expect "unknown game refused" '! run --game nosuch && grep -q "unknown game nosuch" "$T/out"'

[ "$FAILS" = 0 ] || { echo "game_sh_test: $FAILS failed" >&2; exit 1; }
echo "game_sh_test: all passed"

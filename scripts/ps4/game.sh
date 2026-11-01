#!/usr/bin/env bash
# game.sh: Bloodlines and its profile onto the console (milestone g, docs/ps4/HANDOFF-g.md).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/game.sh [--profile-only | --verify-only] [--saves-push DIR | --saves-pull] [--dry-run]

Puts GOG's "Bloodlines - Unofficial Patch" (UP 11.5, the user's extraction in games/bloodlines-up, read
only, never written) at C:\\VTMB of the console's prefix, \$PS4_HOST:$PS4_DATA_ROOT/prefix/drive_c/VTMB,
with its profile and DS4 preset (profiles/vtmb.ini -> $PS4_DATA_ROOT/profiles/, profiles/input/vtmb.input
-> $PS4_DATA_ROOT/input/).

  (default)        the profile, then the game: Vampire.exe, Loader.dll, Bin/, Vampire/, Unofficial_Patch/ and
                   the UP's small root files (not __redist/, app/, commonappdata/, Docs/, the manual, GOG's
                   files or Loader.exe, which the console cannot run), lftp mirror -R --parallel=4 comparing
                   sizes only (an interrupted upload resumes); then every file's size checked against one
                   recursive listing, and build/game-vtmb.manifest written (size, sha256, path)
  --profile-only   only the profile and the preset
  --verify-only    only the size check of what is on the console
  --saves-push DIR put DIR's *.sav (default build/saves/vtmb: host-game.sh --saves-out) into the game's
                   Unofficial_Patch/save on the console, sizes checked
  --saves-pull     fetch the console's Unofficial_Patch/save/*.sav into build/saves/vtmb-console
  --dry-run        print the lftp commands only
USAGE
}

MODE=all; SAVES_DIR=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --profile-only) MODE=profile; shift ;;
        --verify-only) MODE=verify; shift ;;
        --saves-push) MODE=push; SAVES_DIR="${2:-$BUILD_DIR/saves/vtmb}"; shift; [ $# -gt 0 ] && shift ;;
        --saves-pull) MODE=pull; shift ;;
        --dry-run) DRY=1; shift ;;
        *) usage; die "unknown option $1" ;;
    esac
done
need_cmd lftp

GAME_SRC="$REPO_ROOT/games/bloodlines-up"
PROFILE="$REPO_ROOT/profiles/vtmb.ini"
PRESET="$REPO_ROOT/profiles/input/vtmb.input"
DEST="$PS4_DATA_ROOT/prefix/drive_c/VTMB"
SAVE_DEST="$DEST/Unofficial_Patch/save"
MANIFEST="$BUILD_DIR/game-vtmb.manifest"
OPEN="set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2; open ftp://$PS4_HOST:$PS4_FTP_PORT;"
EXCLUDES=(__redist/ app/ commonappdata/ Docs/ manual.pdf 'goggame-*' Loader.exe)

ftp() { # ftp COMMANDS: one lftp session (or print it with --dry-run)
    if [ "$DRY" = 1 ]; then printf 'lftp -c "%s %s"\n' "$OPEN" "$1"; return 0; fi
    lftp -c "$OPEN $1"
}

# "size path" for every file under DIR on the console, paths relative to DIR (lftp's find -l).
remote_sizes() {
    lftp -c "$OPEN cd '$1' && find -l ." 2>/dev/null | python3 -I -c '
import re, sys
for line in sys.stdin:
    m = re.match(r"^(\S+)\s+\S+\s+(\d+)\s+\S+\s+\S+\s+(.*)$", line.rstrip("\n"))
    if m and not m.group(1).startswith("d"):
        print(m.group(2), m.group(3)[2:] if m.group(3).startswith("./") else m.group(3))'
}

# Every local file the mirror sends, as "size path" relative to games/bloodlines-up.
local_sizes() {
    (cd "$GAME_SRC" && find . -type f \
        ! -path './__redist/*' ! -path './app/*' ! -path './commonappdata/*' ! -path './Docs/*' \
        ! -name manual.pdf ! -name 'goggame-*' ! -name Loader.exe -printf '%s %P\n' | LC_ALL=C sort -k2)
}

verify() {
    local want have missing bad n
    want="$(local_sizes | LC_ALL=C sort)"
    log "verify: listing $DEST on the console (one LIST a directory)"
    have="$(remote_sizes "$DEST" | LC_ALL=C sort)"
    [ -n "$have" ] || die "no listing of $DEST (is the console on, GoldHEN's FTP enabled, the game uploaded?)"
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))"
    n="$(printf '%s\n' "$want" | wc -l)"
    bad="$(printf '%s' "$missing" | grep -c . || true)"
    [ "$bad" = 0 ] || printf '%s\n' "$missing" | head -n 20 | while IFS= read -r line; do log "missing or wrong size: $line"; done
    log "verify: $n files, $bad missing or of the wrong size"
    [ "$bad" = 0 ] || die "the game on the console is incomplete: run scripts/ps4/game.sh again (it resumes)"
}

put_profile() {
    [ -f "$PROFILE" ] && [ -f "$PRESET" ] || die "no $PROFILE or $PRESET"
    ftp "mkdir -pf '$PS4_DATA_ROOT/profiles'; mkdir -pf '$PS4_DATA_ROOT/input';
put -O '$PS4_DATA_ROOT/profiles' '$PROFILE'; put -O '$PS4_DATA_ROOT/input' '$PRESET';"
    [ "$DRY" = 1 ] && return 0
    local have
    have="$(remote_sizes "$PS4_DATA_ROOT/profiles" | awk '$2 == "vtmb.ini" { print $1 }')"
    [ "$have" = "$(stat -c %s "$PROFILE")" ] || die "profile upload: remote size ${have:-missing}"
    log "profile: $PS4_DATA_ROOT/profiles/vtmb.ini and input/vtmb.input"
}

case "$MODE" in
    profile) put_profile; exit 0 ;;
    verify) verify; exit 0 ;;
    pull)
        mkdir -p "$BUILD_DIR/saves/vtmb-console"
        ftp "mirror --no-perms --include-glob '*.sav' '$SAVE_DEST' '$BUILD_DIR/saves/vtmb-console';"
        log "saves: $(find "$BUILD_DIR/saves/vtmb-console" -name '*.sav' | wc -l) in $BUILD_DIR/saves/vtmb-console"
        exit 0 ;;
    push)
        [ -d "$SAVES_DIR" ] || die "no $SAVES_DIR (scripts/ps4/host-game.sh --saves-out makes build/saves/vtmb)"
        puts=""
        for f in "$SAVES_DIR"/*.sav; do [ -f "$f" ] && puts="$puts put -O '$SAVE_DEST' '$f';"; done
        [ -n "$puts" ] || die "no *.sav in $SAVES_DIR"
        ftp "mkdir -pf '$SAVE_DEST'; $puts"
        [ "$DRY" = 1 ] && exit 0
        remote="$(remote_sizes "$SAVE_DEST")"
        for f in "$SAVES_DIR"/*.sav; do
            grep -qxF -- "$(stat -c %s "$f") $(basename "$f")" <<<"$remote" || die "save $(basename "$f") did not arrive whole"
        done
        log "saves: $(ls "$SAVES_DIR"/*.sav | wc -l) put into $SAVE_DEST"
        exit 0 ;;
esac

[ -f "$GAME_SRC/Vampire.exe" ] || die "no $GAME_SRC/Vampire.exe (the user's extracted UP install)"
put_profile
ex=""
for e in "${EXCLUDES[@]}"; do ex="$ex --exclude-glob '$e'"; done
log "game: $(local_sizes | wc -l) files, $(du -sh --apparent-size "$GAME_SRC/Vampire" "$GAME_SRC/Unofficial_Patch" "$GAME_SRC/Bin" | awk '{print $1}' | paste -sd+) -> ftp://$PS4_HOST:$PS4_FTP_PORT$DEST"
start=$(date +%s)
ftp "mkdir -pf '$DEST'; mirror -R --no-perms --parallel=4 --only-newer --ignore-time $ex '$GAME_SRC' '$DEST';"
[ "$DRY" = 1 ] && exit 0
log "game: mirror done in $(( $(date +%s) - start )) s"
verify
log "manifest: $MANIFEST (sha256 of every file sent)"
(cd "$GAME_SRC" && local_sizes | while read -r size path; do
    printf '%s %s %s\n' "$size" "$(sha256sum "$path" | cut -d' ' -f1)" "$path"; done) > "$MANIFEST"

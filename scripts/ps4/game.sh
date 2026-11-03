#!/usr/bin/env bash
# game.sh: a game and its profile onto the console: Bloodlines (milestone g, docs/ps4/HANDOFF-g.md) or
# Psychonauts (milestones k-n, docs/ps4/HANDOFF-i.md).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/game.sh [--game vtmb|psychonauts] [--profile-only | --verify-only]
                           [--saves-push DIR | --saves-pull] [--dry-run]

Puts a game (read only from games/, never written) into the console's prefix with its profile and DS4
preset (profiles/<id>.ini -> $PS4_DATA_ROOT/profiles/, profiles/input/<id>.input -> $PS4_DATA_ROOT/input/):

  vtmb (default)   GOG's "Bloodlines - Unofficial Patch" (UP 11.5, games/bloodlines-up) at C:\\VTMB:
                   Vampire.exe, Loader.dll, Bin/, Vampire/, Unofficial_Patch/ and the UP's small root files
                   (not __redist/, app/, commonappdata/, Docs/, the manual, GOG's files or Loader.exe, which
                   the console cannot run); saves are Unofficial_Patch/save/*.sav
  psychonauts      GOG's Psychonauts 2.2.0.13 (games/psychonauts/game) at C:\\Psychonauts, English only (not
                   WorkResource/Sounds/French/ or German/), plus support/app/*.ini in the game folder (the
                   game reads them from its working directory) and profiles/psychonauts.dxvk.conf as
                   C:\\Psychonauts\\dxvk.conf (the same set as host-game.sh --game psychonauts); saves are
                   the whole Profiles/ folder (saves and the bindings INI)

  (default)        the profile, then the game: lftp mirror -R --parallel=4 comparing sizes only (an
                   interrupted upload resumes; a partly sent file is sent again whole), then the extra
                   files, then every file's size checked against one recursive listing, and
                   build/game-<id>.manifest written (size, sha256, path on the console relative to the game)
  --profile-only   only the profile and the preset, sizes checked
  --verify-only    only the size check of what is on the console
  --saves-push DIR vtmb: put DIR's *.sav (default build/saves/vtmb: host-game.sh --saves-out) into
                   Unofficial_Patch/save; psychonauts: mirror DIR (default
                   build/saves/psychonauts/Psychonauts/Profiles) into C:\\Psychonauts\\Profiles; sizes checked
  --saves-pull     fetch the console's saves into build/saves/<id>-console
  --dry-run        print the lftp commands only

PS4_GAME_OPEN replaces the lftp "open" commands (the host test uses a file:// URL).
USAGE
}

GAME=vtmb; MODE=all; SAVES_DIR=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --game) [ $# -ge 2 ] || die "--game needs vtmb or psychonauts"; GAME="$2"; shift 2 ;;
        --profile-only) MODE=profile; shift ;;
        --verify-only) MODE=verify; shift ;;
        --saves-push) MODE=push; if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then SAVES_DIR="$2"; shift; fi; shift ;;
        --saves-pull) MODE=pull; shift ;;
        --dry-run) DRY=1; shift ;;
        *) usage; die "unknown option $1" ;;
    esac
done
need_cmd lftp

# The per-game table. LFTP_EX and FIND_EX name the same files (the mirror's and the size check's view);
# EXTRAS are "source=name" files put into the game folder after the mirror.
case "$GAME" in
    vtmb)
        GAME_SRC="$REPO_ROOT/games/bloodlines-up"
        EXE=Vampire.exe
        DEST="$PS4_DATA_ROOT/prefix/drive_c/VTMB"
        SAVE_DEST="$DEST/Unofficial_Patch/save"
        SAVES_DEFAULT="$BUILD_DIR/saves/vtmb"
        LFTP_EX=(__redist/ app/ commonappdata/ Docs/ manual.pdf 'goggame-*' Loader.exe)
        LFTP_EX_OPT=--exclude-glob
        FIND_EX=(! -path './__redist/*' ! -path './app/*' ! -path './commonappdata/*' ! -path './Docs/*'
                 ! -name manual.pdf ! -name 'goggame-*' ! -name Loader.exe)
        EXTRAS=() ;;
    psychonauts)
        GAME_SRC="$REPO_ROOT/games/psychonauts/game"
        EXE=Psychonauts.exe
        DEST="$PS4_DATA_ROOT/prefix/drive_c/Psychonauts"
        SAVE_DEST="$DEST/Profiles"
        SAVES_DEFAULT="$BUILD_DIR/saves/psychonauts/Psychonauts/Profiles"
        LFTP_EX=('^WorkResource/Sounds/French/' '^WorkResource/Sounds/German/')
        LFTP_EX_OPT=--exclude
        FIND_EX=(! -path './WorkResource/Sounds/French/*' ! -path './WorkResource/Sounds/German/*')
        support="$REPO_ROOT/games/psychonauts/support/app"
        EXTRAS=("$support/AudioSettings.ini=AudioSettings.ini" "$support/DisplaySettings.ini=DisplaySettings.ini"
                "$support/Psychonauts.ini=Psychonauts.ini" "$REPO_ROOT/profiles/psychonauts.dxvk.conf=dxvk.conf") ;;
    *) usage; die "unknown game $GAME (vtmb or psychonauts)" ;;
esac
PROFILE="$REPO_ROOT/profiles/$GAME.ini"
PRESET="$REPO_ROOT/profiles/input/$GAME.input"
MANIFEST="$BUILD_DIR/game-$GAME.manifest"
OPEN="${PS4_GAME_OPEN:-set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2; open ftp://$PS4_HOST:$PS4_FTP_PORT;}"

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

# Every local file the mirror sends, as "size path" relative to the game's source.
local_sizes() {
    (cd "$GAME_SRC" && find . -type f "${FIND_EX[@]}" -printf '%s %P\n' | LC_ALL=C sort -k2)
}

# The extra files as "size name source".
extra_list() {
    local e
    for e in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
        [ -f "${e%%=*}" ] || die "no ${e%%=*}"
        printf '%s %s %s\n' "$(stat -c %s "${e%%=*}")" "${e#*=}" "${e%%=*}"
    done
}

# What the console must hold: the game's files, an extra replacing a game file of the same name.
want_sizes() {
    local extras
    extras="$(extra_list)"
    { local_sizes | NAMES="$(printf '%s\n' "$extras" | awk 'NF { print $2 }')" awk '
        BEGIN { n = split(ENVIRON["NAMES"], a, "\n"); for (i = 1; i <= n; i++) skip[a[i]] = 1 }
        { p = $0; sub(/^[0-9]+ /, "", p); if (!(p in skip)) print }'
      printf '%s\n' "$extras" | awk 'NF { print $1, $2 }'; }
}

verify() {
    local want have missing bad n
    want="$(want_sizes | LC_ALL=C sort)"
    log "verify: listing $DEST on the console (one LIST a directory)"
    have="$(remote_sizes "$DEST" | LC_ALL=C sort)"
    [ -n "$have" ] || die "no listing of $DEST (is the console on, GoldHEN's FTP enabled, the game uploaded?)"
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))"
    n="$(printf '%s\n' "$want" | wc -l)"
    bad="$(printf '%s' "$missing" | grep -c . || true)"
    [ "$bad" = 0 ] || printf '%s\n' "$missing" | head -n 20 | while IFS= read -r line; do log "missing or wrong size: $line"; done
    log "verify: $n files, $bad missing or of the wrong size"
    [ "$bad" = 0 ] || die "the game on the console is incomplete: run scripts/ps4/game.sh --game $GAME again (it resumes)"
}

put_profile() {
    [ -f "$PROFILE" ] && [ -f "$PRESET" ] || die "no $PROFILE or $PRESET"
    ftp "mkdir -pf '$PS4_DATA_ROOT/profiles'; mkdir -pf '$PS4_DATA_ROOT/input';
put -O '$PS4_DATA_ROOT/profiles' '$PROFILE'; put -O '$PS4_DATA_ROOT/input' '$PRESET';"
    [ "$DRY" = 1 ] && return 0
    local have
    have="$(remote_sizes "$PS4_DATA_ROOT/profiles" | awk -v f="$GAME.ini" '$2 == f { print $1 }')"
    [ "$have" = "$(stat -c %s "$PROFILE")" ] || die "profile upload: remote size ${have:-missing}"
    have="$(remote_sizes "$PS4_DATA_ROOT/input" | awk -v f="$GAME.input" '$2 == f { print $1 }')"
    [ "$have" = "$(stat -c %s "$PRESET")" ] || die "preset upload: remote size ${have:-missing}"
    log "profile: $PS4_DATA_ROOT/profiles/$GAME.ini and input/$GAME.input"
}

case "$MODE" in
    profile) put_profile; exit 0 ;;
    verify) verify; exit 0 ;;
    pull)
        mkdir -p "$BUILD_DIR/saves/$GAME-console"
        if [ "$GAME" = vtmb ]; then
            ftp "mirror --no-perms --include-glob '*.sav' '$SAVE_DEST' '$BUILD_DIR/saves/vtmb-console';"
        else
            ftp "mirror --no-perms '$SAVE_DEST' '$BUILD_DIR/saves/$GAME-console';"
        fi
        log "saves: $(find "$BUILD_DIR/saves/$GAME-console" -type f | wc -l) files in $BUILD_DIR/saves/$GAME-console"
        exit 0 ;;
    push)
        SAVES_DIR="${SAVES_DIR:-$SAVES_DEFAULT}"
        [ -d "$SAVES_DIR" ] || die "no $SAVES_DIR (scripts/ps4/host-game.sh --saves-out makes build/saves/$GAME)"
        if [ "$GAME" = vtmb ]; then
            puts=""
            for f in "$SAVES_DIR"/*.sav; do [ -f "$f" ] && puts="$puts put -O '$SAVE_DEST' '$f';"; done
            [ -n "$puts" ] || die "no *.sav in $SAVES_DIR"
            ftp "mkdir -pf '$SAVE_DEST'; $puts"
            [ "$DRY" = 1 ] && exit 0
            remote="$(remote_sizes "$SAVE_DEST")"
            for f in "$SAVES_DIR"/*.sav; do
                grep -qxF -- "$(stat -c %s "$f") $(basename "$f")" <<<"$remote" || die "save $(basename "$f") did not arrive whole"
            done
            log "saves: $(find "$SAVES_DIR" -maxdepth 1 -name '*.sav' | wc -l) put into $SAVE_DEST"
        else
            ftp "mkdir -pf '$SAVE_DEST'; mirror -R --no-perms '$SAVES_DIR' '$SAVE_DEST';"
            [ "$DRY" = 1 ] && exit 0
            missing="$(LC_ALL=C comm -23 <(cd "$SAVES_DIR" && find . -type f -printf '%s %P\n' | LC_ALL=C sort) \
                <(remote_sizes "$SAVE_DEST" | LC_ALL=C sort))"
            [ -z "$missing" ] || die "saves did not arrive whole: $(printf '%s' "$missing" | head -n 3 | paste -sd';')"
            log "saves: $(find "$SAVES_DIR" -type f | wc -l) files mirrored into $SAVE_DEST"
        fi
        exit 0 ;;
esac

[ -f "$GAME_SRC/$EXE" ] || die "no $GAME_SRC/$EXE (the user's extracted install)"
put_profile
ex=""
for e in "${LFTP_EX[@]}"; do ex="$ex $LFTP_EX_OPT '$e'"; done
puts=""
while read -r _ name src; do puts="$puts put '$src' -o '$DEST/$name';"; done < <(extra_list)
log "game: $(want_sizes | awk '{ n++; b += $1 } END { printf "%d files, %d B", n, b }') -> ftp://$PS4_HOST:$PS4_FTP_PORT$DEST"
start=$(date +%s)
ftp "mkdir -pf '$DEST'; mirror -R --no-perms --parallel=4 --ignore-time $ex '$GAME_SRC' '$DEST';$puts"
[ "$DRY" = 1 ] && exit 0
log "game: mirror done in $(( $(date +%s) - start )) s"
verify
log "manifest: $MANIFEST (sha256 of every file sent)"
declare -A extra_src=()
while read -r _ name src; do extra_src[$name]="$src"; done < <(extra_list)
while read -r size path; do
    src="${extra_src[$path]:-$GAME_SRC/$path}"
    printf '%s %s %s\n' "$size" "$(sha256sum "$src" | cut -d' ' -f1)" "$path"
done < <(want_sizes) > "$MANIFEST"

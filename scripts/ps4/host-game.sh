#!/usr/bin/env bash
# host-game.sh: Bloodlines on the laptop, under the desktop host Wine (milestone g, docs/ps4/HANDOFF-g.md H2/H3).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/host-game.sh [--setup-only] [--census] [--fullscreen] [--gpu NAME] [--no-hud]
                                [--batch-stats-every N] [--saves-out]

Runs Vampire: The Masquerade - Bloodlines (GOG, Unofficial Patch 11.5) as the console does,
C:\\VTMB\\Vampire.exe -game Unofficial_Patch, under the desktop Wine of build.sh wine-desktop
(X11 through XWayland, PulseAudio, FreeType), so it can be played to the first map and saved there.

  The game:   a reflink copy of games/bloodlines-up (read only, never written) in build/host-game/vtmb;
              saves and configs go there.
  The prefix: build/prefix-desktop (wow64), its C:\\VTMB a link to that copy, DXVK $DXVK_VERSION's 32-bit
              d3d9.dll in syswow64 (the fork's pin, SHA-256 checked) with d3d9=n.
  The run:    the host's native WoW64 CPU, Vulkan batching on (PW_VK_BATCH=1, PW_VK_BATCH_STATS=1:
              one PW_VK_BATCH line per present, which tools/summarize_vk_batch.py reads), in a
              1920x1080 Wine virtual desktop (the console's desktop size); Wine's output to
              logs/<ts>-host-vtmb.log.

  --setup-only           make the copy and the prefix, do not start the game
  --census               WINEDEBUG=+loaddll as well: every DLL the game loads, and where
  --fullscreen           no virtual desktop (the game's own mode changes, through XWayland)
  --gpu NAME             DXVK_FILTER_DEVICE_NAME=NAME (e.g. Intel, NVIDIA); default: DXVK's choice
  --no-hud               no DXVK HUD (default: fps,frametimes,gpuload)
  --batch-stats-every N  PW_VK_BATCH_STATS_EVERY=N (default 1; the summariser needs 1)
  --saves-out            copy the game's saves (Unofficial_Patch/save/*.sav) to build/saves/vtmb and stop
USAGE
}

SETUP_ONLY=0; CENSUS=0; FULLSCREEN=0; GPU=""; HUD="fps,frametimes,gpuload"; EVERY=1; SAVES_OUT=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --setup-only) SETUP_ONLY=1; shift ;;
        --census) CENSUS=1; shift ;;
        --fullscreen) FULLSCREEN=1; shift ;;
        --gpu) GPU="${2:?--gpu needs a name}"; shift 2 ;;
        --no-hud) HUD=""; shift ;;
        --batch-stats-every) EVERY="${2:?--batch-stats-every needs N}"; shift 2 ;;
        --saves-out) SAVES_OUT=1; shift ;;
        *) usage; die "unknown option $1" ;;
    esac
done
[[ "$EVERY" =~ ^[0-9]+$ ]] && [ "$EVERY" -ge 1 ] || die "--batch-stats-every takes a positive number"

GAME_SRC="$REPO_ROOT/games/bloodlines-up"       # the user's extracted install (HANDOFF-f.md "Games on the host")
GAME="$BUILD_DIR/host-game/vtmb"
PREFIX="$BUILD_DIR/prefix-desktop"
WINE_TREE="$PROSPERO_WIN_DIR/.deps/wine-host-desktop"
WINE="$WINE_TREE/install/usr/bin/wine"
SAVES="$BUILD_DIR/saves/vtmb"

if [ "$SAVES_OUT" = 1 ]; then
    [ -d "$GAME/Unofficial_Patch/save" ] || die "no $GAME/Unofficial_Patch/save: run the game first"
    mkdir -p "$SAVES"
    find "$GAME/Unofficial_Patch/save" -maxdepth 1 -type f -name '*.sav' -exec cp -p --remove-destination {} "$SAVES/" \;
    log "saves: $(find "$SAVES" -name '*.sav' | wc -l) in $SAVES"
    find "$SAVES" -name '*.sav' -printf '  %TY-%Tm-%Td %TH:%TM  %8s  %f\n' | sort >&2
    exit 0
fi

[ -x "$WINE" ] || die "no desktop Wine at $WINE: scripts/ps4/build.sh wine-desktop"
[ -f "$GAME_SRC/Vampire.exe" ] || die "no $GAME_SRC/Vampire.exe (the user's extracted UP install)"

# The game: a copy-on-write copy, so the game's own writes (saves, configs) never reach games/.
if [ ! -f "$GAME/Vampire.exe" ]; then
    log "game: $GAME_SRC -> $GAME (reflink copy)"
    mkdir -p "$(dirname "$GAME")"
    cp -a --reflink=auto "$GAME_SRC" "$GAME.part"
    mv -f "$GAME.part" "$GAME"
fi

# The prefix: wineboot once, without the Mono and Gecko installers; DXVK's d3d9 into syswow64.
export WINEPREFIX="$PREFIX" WINEARCH=wow64
if [ ! -f "$PREFIX/system.reg" ]; then
    log "prefix: wineboot --init in $PREFIX"
    WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all "$WINE" wineboot --init >/dev/null 2>&1 ||
        die "wineboot --init failed in $PREFIX"
    WINEDEBUG=-all "$WINE_TREE/install/usr/bin/wineserver" -w || true
fi
[ -d "$PREFIX/drive_c/windows/syswow64" ] || die "$PREFIX has no syswow64: not a wow64 prefix"
tar -xzf "$(dxvk_archive)" -C "$PREFIX/drive_c/windows/syswow64" --strip-components=2 "dxvk-$DXVK_VERSION/x32/d3d9.dll"
ln -sfn "$GAME" "$PREFIX/drive_c/VTMB"
log "prefix: $PREFIX, C:\\VTMB -> $GAME, DXVK $DXVK_VERSION x32 d3d9.dll in syswow64"
[ "$SETUP_ONLY" = 0 ] || exit 0

mkdir -p "$LOGS_DIR"
LOG="$LOGS_DIR/$(timestamp)-host-vtmb.log"
export WINEDLLOVERRIDES="d3d9=n;mscoree,mshtml="
export WINEDEBUG="err+all,fixme-all"
[ "$CENSUS" = 1 ] && WINEDEBUG="$WINEDEBUG,+loaddll"
export PW_VK_BATCH=1 PW_VK_BATCH_STATS=1 PW_VK_BATCH_STATS_EVERY="$EVERY"
if [ -n "$HUD" ]; then export DXVK_HUD="$HUD"; else unset DXVK_HUD; fi
if [ -n "$GPU" ]; then export DXVK_FILTER_DEVICE_NAME="$GPU"; fi
cmd=("$WINE")
[ "$FULLSCREEN" = 1 ] || cmd+=(explorer "/desktop=vtmb,1920x1080")
cmd+=('C:\VTMB\Vampire.exe' -game Unofficial_Patch)
log "run: ${cmd[*]} (WINEDEBUG=$WINEDEBUG${GPU:+, DXVK_FILTER_DEVICE_NAME=$GPU}); log $LOG"
cd "$GAME"
set +e
"${cmd[@]}" > "$LOG" 2>&1
status=$?
set -e
log "Bloodlines exited with $status; $(grep -c '^PW_VK_BATCH \|:PW_VK_BATCH \|PW_VK_BATCH version' "$LOG" || true) PW_VK_BATCH lines in $LOG"
log "saves now: $(find "$GAME/Unofficial_Patch/save" -maxdepth 1 -name '*.sav' 2>/dev/null | wc -l) (--saves-out copies them)"

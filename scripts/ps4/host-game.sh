#!/usr/bin/env bash
# host-game.sh: a game on the laptop, under the desktop host Wine: Bloodlines (milestone g, docs/ps4/HANDOFF-g.md
# H2/H3) and Psychonauts (milestone j, docs/ps4/HANDOFF-i.md).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/host-game.sh [--game vtmb|psychonauts] [--setup-only] [--census] [--fullscreen] [--gpu NAME]
                                [--no-hud] [--batch-stats-every N] [--saves-out]
                                [--pad auto|/dev/input/eventN | --no-pad] [--debug CHANNELS] [--test [--seconds N]]
       scripts/ps4/host-game.sh --game psychonauts --parse LOG [--session-s N]

Runs a game as the console does, under the desktop Wine of build.sh wine-desktop (X11 through XWayland,
PulseAudio, FreeType), so it can be played on the laptop and saved at fixed spots. Both games run on the host's
native WoW64 CPU with DXVK $DXVK_VERSION's 32-bit d3d9.dll in syswow64 (the fork's pin, SHA-256 checked) and
d3d9=n, Vulkan batching on (PW_VK_BATCH=1, PW_VK_BATCH_STATS=1: one PW_VK_BATCH line per present, which
tools/summarize_vk_batch.py reads), in a 1920x1080 Wine virtual desktop (the console's desktop size).

--game vtmb (the default): Vampire: The Masquerade - Bloodlines (GOG, Unofficial Patch 11.5),
C:\\VTMB\\Vampire.exe -game Unofficial_Patch.
  The game:   a reflink copy of games/bloodlines-up (read only, never written) in build/host-game/vtmb;
              saves and configs go there.
  The prefix: build/prefix-desktop (wow64), its C:\\VTMB a link to that copy.
  The log:    logs/<ts>-host-vtmb.log.

--game psychonauts: Psychonauts (GOG 2.2.0.13), C:\\Psychonauts\\Psychonauts.exe, no arguments, from the
working directory C:\\Psychonauts (the game reads its INIs and writes its saves there; Double Fine documents
glitches off C:).
  The prefix: build/prefix-desktop-psychonauts (wow64; never build/prefix-desktop), winebus's "Enable SDL" 0.
  The game:   a reflink copy of games/psychonauts/game (read only, never written) in the prefix's
              drive_c/Psychonauts itself, not behind a link (a link would make the working directory Z:\\...),
              without WorkResource/Sounds/{French,German} (the console's English-only set), with
              support/app/*.ini in its root and profiles/psychonauts.dxvk.conf as dxvk.conf
              (DXVK_CONFIG_FILE=C:\\Psychonauts\\dxvk.conf: d3d9.maxFrameRate = 60). build/host-game/psychonauts
              links to it. Setup checks that Wine sees that directory as C:\\Psychonauts.
  The pad:    a DualShock 4 as XInput controller 0 through the console's path (Wine patches 0470/0471): the fork's
              build/host/host_pad_evdev.so preloaded, fed from evdev. The touchpad's left half is Back, its right
              half the mark ("host_pad mark N" in the log; never reaches the game). The game looks for a
              controller only at startup: plug the pad in first.
  The log:    logs/<ts>-host-psychonauts-j.log, Wine's output with +loaddll, then at the game's exit the line
                PS4WINE j psychonauts exe_base= dll_missing= presents= save_new= pad_reads= session_s= ...
              that check.sh j reads (docs/ps4/HANDOFF-i.md), and a census of the files the session wrote.
              dll_missing counts the game's missing DLLs: imports Wine could not satisfy for a module under
              C:\Psychonauts (the EXE and its shipped DLLs), plus each DLL the EXE imports or loads by name
              (OpenAL32) that never loaded (listed as dll_absent=). Missing imports of Wine's own modules (its
              Indeo codec ir50_32 wants winegstreamer, which neither this Wine nor the console's has) are
              dll_missing_wine=, recorded, not gated.
              save_new is 1 when a file under a SavedGame<N> path (any depth, any case) in the game or in the
              prefix's drive_c/users is newer than the session start; pad_reads counts the game's reads of
              controller 0 while it was connected. Each file written (up to 4 MiB) is kept in
              build/host-game/psychonauts-writes/<ts>/ for comparing sessions.

  --setup-only           make the copy and the prefix, do not start the game
  --census               vtmb: WINEDEBUG=+loaddll as well (psychonauts always has it)
  --fullscreen           no virtual desktop (the game's own mode changes, through XWayland)
  --gpu NAME             DXVK_FILTER_DEVICE_NAME=NAME (e.g. Intel, NVIDIA); default: DXVK's choice
  --no-hud               no DXVK HUD (default: fps,frametimes,gpuload)
  --batch-stats-every N  PW_VK_BATCH_STATS_EVERY=N (default 1; the summariser and presents= need 1)
  --saves-out            copy the game's saves to build/saves/<game> and stop (vtmb: Unofficial_Patch/save/*.sav;
                         psychonauts: every SavedGame<N> path, with its directories)
  --pad auto|NODE        psychonauts: the pad's event node (default auto: the first Sony controller under
                         /dev/input, and its touchpad); the run stops when none is found
  --no-pad               psychonauts: no pad (controller 0 reads disconnected; j's pad_reads cannot pass)
  --debug CHANNELS       added to WINEDEBUG (e.g. +keyboard, trace+xinput)
  --test                 the tester's copy instead of the user's: build/host-test/<game> and
                         build/host-test/prefix-desktop-<game>
  --seconds N            with --test: end the game after N s (wineserver -k of that prefix)
  --parse LOG            psychonauts: print the fields host-game.sh takes from a session's log (Wine's output),
                         without running anything; --session-s N gives fps_avg its divisor (tests)
USAGE
}

GAME_ID=vtmb; SETUP_ONLY=0; CENSUS=0; FULLSCREEN=0; GPU=""; HUD="fps,frametimes,gpuload"; EVERY=1; SAVES_OUT=0
PAD=auto; PAD_GIVEN=0; DEBUG=""; DEBUG_GIVEN=0; TEST=0; SECONDS_MAX=0; PARSE=""; PARSE_S=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --game) GAME_ID="${2:?--game needs vtmb or psychonauts}"; shift 2 ;;
        --setup-only) SETUP_ONLY=1; shift ;;
        --census) CENSUS=1; shift ;;
        --fullscreen) FULLSCREEN=1; shift ;;
        --gpu) GPU="${2:?--gpu needs a name}"; shift 2 ;;
        --no-hud) HUD=""; shift ;;
        --batch-stats-every) EVERY="${2:?--batch-stats-every needs N}"; shift 2 ;;
        --saves-out) SAVES_OUT=1; shift ;;
        --pad) PAD="${2:?--pad needs auto or an event node}"; PAD_GIVEN=1; shift 2 ;;
        --no-pad) PAD=none; PAD_GIVEN=1; shift ;;
        --debug) DEBUG="${2:?--debug needs channels}"; DEBUG_GIVEN=1; shift 2 ;;
        --test) TEST=1; shift ;;
        --seconds) SECONDS_MAX="${2:?--seconds needs N}"; shift 2 ;;
        --parse) PARSE="${2:?--parse needs a log}"; shift 2 ;;
        --session-s) PARSE_S="${2:?--session-s needs N}"; shift 2 ;;
        *) usage; die "unknown option $1" ;;
    esac
done
[[ "$EVERY" =~ ^[0-9]+$ ]] && [ "$EVERY" -ge 1 ] || die "--batch-stats-every takes a positive number"
[[ "$SECONDS_MAX" =~ ^[0-9]+$ ]] || die "--seconds takes a number"
[ "$SECONDS_MAX" = 0 ] || [ "$TEST" = 1 ] || die "--seconds only with --test (the user's runs end when the user quits)"
case "$GAME_ID" in vtmb|psychonauts) ;; *) die "--game takes vtmb or psychonauts" ;; esac
if [ "$GAME_ID" = vtmb ] && { [ "$PAD_GIVEN" = 1 ] || [ "$DEBUG_GIVEN" = 1 ] || [ -n "$PARSE" ]; }; then
    die "--pad, --no-pad, --debug and --parse are psychonauts' (vtmb runs as before)"
fi

WINE_TREE="$PROSPERO_WIN_DIR/.deps/wine-host-desktop"
WINE="$WINE_TREE/install/usr/bin/wine"
WINESERVER="$WINE_TREE/install/usr/bin/wineserver"

# ---- Bloodlines (milestone g): unchanged but for --test ----
if [ "$GAME_ID" = vtmb ]; then
    GAME_SRC="$REPO_ROOT/games/bloodlines-up"       # the user's extracted install (HANDOFF-f.md "Games on the host")
    GAME="$BUILD_DIR/host-game/vtmb"
    PREFIX="$BUILD_DIR/prefix-desktop"
    SAVES="$BUILD_DIR/saves/vtmb"
    if [ "$TEST" = 1 ]; then
        GAME="$BUILD_DIR/host-test/vtmb"
        PREFIX="$BUILD_DIR/host-test/prefix-desktop-vtmb"
        SAVES="$BUILD_DIR/host-test/saves/vtmb"
    fi

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
        WINEDEBUG=-all "$WINESERVER" -w || true
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
    if [ "$SECONDS_MAX" -gt 0 ]; then
        "${cmd[@]}" > "$LOG" 2>&1 &
        pid=$!
        for _ in $(seq "$SECONDS_MAX"); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
        kill -0 "$pid" 2>/dev/null && { log "--seconds $SECONDS_MAX: wineserver -k in $PREFIX"; "$WINESERVER" -k; }
        wait "$pid"
    else
        "${cmd[@]}" > "$LOG" 2>&1
    fi
    status=$?
    set -e
    log "Bloodlines exited with $status; $(grep -c '^PW_VK_BATCH \|:PW_VK_BATCH \|PW_VK_BATCH version' "$LOG" || true) PW_VK_BATCH lines in $LOG"
    log "saves now: $(find "$GAME/Unofficial_Patch/save" -maxdepth 1 -name '*.sav' 2>/dev/null | wc -l) (--saves-out copies them)"
    exit 0
fi

# ---- Psychonauts (milestone j) ----
GAME_SRC="$REPO_ROOT/games/psychonauts/game"        # innoextract --gog output (HANDOFF-i.md "Resume here"), read only
SUPPORT_SRC="$REPO_ROOT/games/psychonauts/support/app"
DXVK_CONF="$REPO_ROOT/profiles/psychonauts.dxvk.conf"
if [ "$TEST" = 1 ]; then
    PREFIX="$BUILD_DIR/host-test/prefix-desktop-psychonauts"
    LINK="$BUILD_DIR/host-test/psychonauts"
    KEEP="$BUILD_DIR/host-test/psychonauts-writes"
    SAVES="$BUILD_DIR/host-test/saves/psychonauts"
else
    PREFIX="$BUILD_DIR/prefix-desktop-psychonauts"
    LINK="$BUILD_DIR/host-game/psychonauts"
    KEEP="$BUILD_DIR/host-game/psychonauts-writes"
    SAVES="$BUILD_DIR/saves/psychonauts"
fi
[ "$PREFIX" != "$BUILD_DIR/prefix-desktop" ] || die "internal: psychonauts must never use build/prefix-desktop"
GAME="$PREFIX/drive_c/Psychonauts"
SHIM="$PROSPERO_WIN_DIR/build/host/host_pad_evdev.so"
MONITOR="$PROSPERO_WIN_DIR/build/host/host_pad_monitor"

# Files under a SavedGame<N> path, in the game and in the prefix's user folders, newer than $1 (or all).
save_files() {
    local newer=()
    [ -n "${1:-}" ] && newer=(-newer "$1")
    find "$GAME" "$PREFIX/drive_c/users" -type f "${newer[@]}" -ipath '*/savedgame[0-9]*' 2>/dev/null || true
}

# The DLLs Psychonauts.exe imports, and OpenAL32 (its LoadLibraryA), lower case without .dll (HANDOFF-i.md A).
GAME_DLLS="dinput8 d3d9 d3dx9_40 winmm dsound binkw32 isactwin audiodrv xinput1_3 steam_api kernel32 user32 shell32
ole32 oleaut32 msvcr90 openal32"

# The j line's fields that come from Wine's output in $1, one key=value a word; $2 is the session's seconds.
log_fields() {
    local log="$1" secs="$2" base batch p0 c0 p1 c1 pad_line loaded absent="" d game_miss wine_miss
    local presents=- fps_avg=- crossings=-
    base="$(grep -aoE 'Loaded L"[^"]*\\Psychonauts\.exe" at [0-9A-Fa-f]+' "$log" | tail -n1 | sed -E 's/.* at //' | tr 'A-F' 'a-f')"
    game_miss="$(grep -aE 'err:module:import_dll Library .* not found|Loading library .* failed' "$log" |
                 grep -aiE 'needed by L"c:\\\\psychonauts\\\\' | sed -E 's/.*(Library|library) ([^ ]+) \(which.*/\2/; s/\.dll$//I' |
                 tr '[:upper:]' '[:lower:]' || true)"
    wine_miss="$(grep -aE 'err:module:import_dll Library .* not found|Loading library .* failed' "$log" |
                 grep -aviE 'needed by L"c:\\\\psychonauts\\\\' | grep -c . || true)"
    loaded=" $(grep -aoE 'Loaded L"[^"]*"' "$log" | sed -E 's/.*\\//; s/"$//; s/\.dll$//I' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
    for d in $GAME_DLLS; do [[ "$loaded" == *" $d "* ]] || absent+="${absent:+,}$d"; done
    batch="$(grep -a '^PW_VK_BATCH ' "$log" || true)"
    if [ -n "$batch" ]; then
        read -r p0 c0 p1 c1 < <(awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
                                       if (NR == 1) { p0 = v["present"]; c0 = v["wine_unix_crossings"] }
                                       p1 = v["present"]; c1 = v["wine_unix_crossings"] }
                                     END { print p0, c0, p1, c1 }' <<<"$batch")
        if [[ "$p0$p1$c0$c1" =~ ^[0-9]+$ ]] && [ -n "$p0" ] && [ -n "$c1" ]; then
            presents="$p1"
            [ "$secs" -gt 0 ] && fps_avg="$(awk -v p="$p1" -v s="$secs" 'BEGIN { printf "%.1f", p / s }')"
            [ "$p1" -gt "$p0" ] && crossings=$(( (c1 - c0) / (p1 - p0) ))
        fi
    fi
    pad_line="$(grep -aE '^host_pad (summary|progress) ' "$log" | tail -n1 || true)"
    padf() { local v; v="$(sed -nE "s/.* $1=([^ ]*).*/\\1/p" <<<"$pad_line")"; printf '%s' "${v:--}"; }
    printf 'exe_base=%s dll_missing=%s dll_missing_wine=%s dll_absent=%s presents=%s fps_avg=%s crossings_per_frame=%s' \
        "${base:+0x}${base:--}" "$(printf '%s\n%s\n' "$game_miss" "$(tr ',' '\n' <<<"$absent")" | grep . | sort -u | grep -c . || true)" "$wine_miss" "${absent:--}" \
        "$presents" "$fps_avg" "$crossings"
    printf ' pad_reads=%s pad_calls=%s pad_first_read_ms=%s rumble_events=%s rumble=%s marks=%s' \
        "$(padf connected_reads)" "$(padf reads)" "$(padf first_read_ms)" "$(padf rumble_events)" "$(padf rumble)" "$(padf marks)"
    printf ' dxvk_conf=%s steam_init=%s\n' \
        "$(grep -aq 'Found config file' "$log" && echo found || echo -)" "$(grep -aq 'S_API FAIL' "$log" && echo fail || echo -)"
}

if [ -n "$PARSE" ]; then
    [ -f "$PARSE" ] || die "no such log: $PARSE"
    log_fields "$PARSE" "$PARSE_S"
    exit 0
fi

if [ "$SAVES_OUT" = 1 ]; then
    [ -d "$GAME" ] || die "no $GAME: run the game first"
    n=0
    while IFS= read -r f; do
        rel="${f#"$PREFIX/drive_c/"}"
        mkdir -p "$SAVES/$(dirname "$rel")"
        cp -p --remove-destination "$f" "$SAVES/$rel"
        n=$((n + 1))
    done < <(save_files)
    log "saves: $n files under SavedGame<N> paths copied to $SAVES (paths from drive_c)"
    find "$SAVES" -type f -printf '  %TY-%Tm-%Td %TH:%TM  %8s  %P\n' 2>/dev/null | sort >&2
    exit 0
fi

[ -x "$WINE" ] || die "no desktop Wine at $WINE: scripts/ps4/build.sh wine-desktop"
[ -f "$GAME_SRC/Psychonauts.exe" ] || die "no $GAME_SRC/Psychonauts.exe (innoextract --gog -d games/psychonauts)"
[ -f "$DXVK_CONF" ] || die "no $DXVK_CONF"

# The prefix first (the copy lives in its drive_c): wineboot once, without the Mono and Gecko installers.
export WINEPREFIX="$PREFIX" WINEARCH=wow64
if [ ! -f "$PREFIX/system.reg" ]; then
    log "prefix: wineboot --init in $PREFIX"
    mkdir -p "$(dirname "$PREFIX")"
    WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all "$WINE" wineboot --init >/dev/null 2>&1 ||
        die "wineboot --init failed in $PREFIX"
    WINEDEBUG=-all "$WINESERVER" -w || true
fi
[ -d "$PREFIX/drive_c/windows/syswow64" ] || die "$PREFIX has no syswow64: not a wow64 prefix"
# This Wine has neither SDL nor udev (config.h), so winebus finds no controller anyway; the value records
# that the pad's only route is the preloaded title pad, as on the console.
if ! grep -q '"Enable SDL"=dword:00000000' "$PREFIX/system.reg"; then
    WINEDEBUG=-all "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\winebus' /v 'Enable SDL' /t REG_DWORD /d 0 /f \
        >/dev/null 2>&1 || die "reg add winebus Enable SDL failed"
    WINEDEBUG=-all "$WINESERVER" -w || true
fi
tar -xzf "$(dxvk_archive)" -C "$PREFIX/drive_c/windows/syswow64" --strip-components=2 "dxvk-$DXVK_VERSION/x32/d3d9.dll"

# The game: a copy-on-write copy in drive_c, so the game's own writes never reach games/.
if [ ! -f "$GAME/Psychonauts.exe" ]; then
    log "game: $GAME_SRC -> $GAME (reflink copy, English only)"
    rm -rf "$GAME.part"
    cp -a --reflink=auto "$GAME_SRC" "$GAME.part"
    rm -rf "$GAME.part/WorkResource/Sounds/French" "$GAME.part/WorkResource/Sounds/German"
    cp "$SUPPORT_SRC"/*.ini "$GAME.part/"
    mv -f "$GAME.part" "$GAME"
fi
cp "$DXVK_CONF" "$GAME/dxvk.conf"
mkdir -p "$(dirname "$LINK")"
ln -sfn "$GAME" "$LINK"
cwd="$(cd "$GAME" && WINEDEBUG=-all "$WINE" cmd /c cd 2>/dev/null | tr -d '\r' | tail -n1)"
[ "$cwd" = 'C:\Psychonauts' ] || die "Wine sees $GAME as '$cwd', not C:\\Psychonauts"
log "prefix: $PREFIX, C:\\Psychonauts = $GAME ($LINK links to it), DXVK $DXVK_VERSION x32 d3d9.dll, dxvk.conf"
[ "$SETUP_ONLY" = 0 ] || exit 0

# The pad: the shim and the nodes.
PAD_NODE=""; TOUCH_NODE=""
if [ "$PAD" != none ]; then
    make -s -C "$PROSPERO_WIN_DIR" build/host/host_pad_evdev.so build/host/host_pad_monitor >/dev/null ||
        die "building the fork's host_pad_evdev.so failed"
    if [ "$PAD" = auto ]; then
        found="$("$MONITOR" --list || true)"
        PAD_NODE="$(sed -n 's/^pad=\([^ ]*\) .*/\1/p' <<<"$found")"
        TOUCH_NODE="$(sed -n 's/.* touch=\(.*\)$/\1/p' <<<"$found")"
        [ -n "$PAD_NODE" ] && [ "$PAD_NODE" != - ] ||
            die "no DualShock 4 under /dev/input (plug it in, or --no-pad): host_pad_monitor --list said '$found'"
        [ "$TOUCH_NODE" != - ] || TOUCH_NODE=none
    else
        PAD_NODE="$PAD"; TOUCH_NODE=""
    fi
    [ -r "$PAD_NODE" ] || die "cannot read $PAD_NODE (no uaccess ACL and not in group input?)"
    [ -w "$PAD_NODE" ] || log "pad: $PAD_NODE is not writable: no rumble (recorded as rumble=unavailable)"
    log "pad: $PAD_NODE, touchpad ${TOUCH_NODE:-found by the shim}, through $SHIM"
fi

mkdir -p "$LOGS_DIR"
TS="$(timestamp)"
LOG="$LOGS_DIR/$TS-host-psychonauts-j.log"
MARK="$(mktemp "${TMPDIR:-/tmp}/host-psychonauts-start.XXXXXX")"
trap 'rm -f "$MARK"' EXIT
export WINEDLLOVERRIDES="d3d9=n;mscoree,mshtml="
export WINEDEBUG="err+all,fixme-all,+loaddll${DEBUG:+,$DEBUG}"
export DXVK_CONFIG_FILE='C:\Psychonauts\dxvk.conf'
export PW_VK_BATCH=1 PW_VK_BATCH_STATS=1 PW_VK_BATCH_STATS_EVERY="$EVERY"
if [ -n "$HUD" ]; then export DXVK_HUD="$HUD"; else unset DXVK_HUD; fi
if [ -n "$GPU" ]; then export DXVK_FILTER_DEVICE_NAME="$GPU"; fi
if [ "$PAD" != none ]; then
    export PW_SINK_PROCESS=Psychonauts PW_HOST_PAD="$PAD_NODE" LD_PRELOAD="$SHIM${LD_PRELOAD:+:$LD_PRELOAD}"
    if [ -n "$TOUCH_NODE" ]; then export PW_HOST_PAD_TOUCH="$TOUCH_NODE"; fi
fi
cmd=("$WINE")
[ "$FULLSCREEN" = 1 ] || cmd+=(explorer "/desktop=psychonauts,1920x1080")
cmd+=('C:\Psychonauts\Psychonauts.exe')
log "run: ${cmd[*]} (WINEDEBUG=$WINEDEBUG${GPU:+, DXVK_FILTER_DEVICE_NAME=$GPU}); log $LOG"
cd "$GAME"
touch "$MARK"
start=$(date +%s)
set +e
if [ "$SECONDS_MAX" -gt 0 ]; then
    "${cmd[@]}" > "$LOG" 2>&1 &
    pid=$!
    for _ in $(seq "$SECONDS_MAX"); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -0 "$pid" 2>/dev/null && { log "--seconds $SECONDS_MAX: wineserver -k in $PREFIX"; "$WINESERVER" -k; }
    wait "$pid"
else
    "${cmd[@]}" > "$LOG" 2>&1
fi
status=$?
set -e
end=$(date +%s)
# The game's exit leaves the server and explorer running: wait for them, so every write is on disk.
WINEDEBUG=-all timeout 30 "$WINESERVER" -w || true
session_s=$((end - start))

# The j line (docs/ps4/HANDOFF-i.md: check.sh j). A field with no source is "-".
declare -A J=()
for kv in $(log_fields "$LOG" "$session_s"); do J["${kv%%=*}"]="${kv#*=}"; done
save_new=0; [ -n "$(save_files "$MARK")" ] && save_new=1
dumps="$(find "$GAME" -maxdepth 1 -newer "$MARK" -iname 'PsychoDump*' | wc -l)"
LINE="PS4WINE j psychonauts exe_base=${J[exe_base]} dll_missing=${J[dll_missing]} presents=${J[presents]} save_new=$save_new"
LINE+=" pad_reads=${J[pad_reads]} session_s=$session_s fps_avg=${J[fps_avg]} crossings_per_frame=${J[crossings_per_frame]}"
LINE+=" dll_missing_wine=${J[dll_missing_wine]} dll_absent=${J[dll_absent]} dxvk_conf=${J[dxvk_conf]}"
LINE+=" steam_init=${J[steam_init]} exit=$status dumps=$dumps pad_calls=${J[pad_calls]} pad_first_read_ms=${J[pad_first_read_ms]}"
LINE+=" rumble_events=${J[rumble_events]} rumble=${J[rumble]} marks=${J[marks]} test=$TEST"
printf '%s\n' "$LINE" >> "$LOG"

# What the session wrote: the save path and the bindings file show up here. Kept for comparing sessions.
mkdir -p "$KEEP/$TS"
{
    echo "host-game census: files written during the session (path from drive_c, bytes)"
    find "$GAME" "$PREFIX/drive_c/users" -type f -newer "$MARK" -printf '%p %s\n' 2>/dev/null |
        sed "s|^$PREFIX/drive_c/||" | sort || true
} >> "$LOG"
while IFS= read -r f; do
    rel="${f#"$PREFIX/drive_c/"}"
    mkdir -p "$KEEP/$TS/$(dirname "$rel")"
    cp -p "$f" "$KEEP/$TS/$rel"
done < <(find "$GAME" "$PREFIX/drive_c/users" -type f -newer "$MARK" -size -4M 2>/dev/null || true)

log "Psychonauts exited with $status after ${session_s}s; log $LOG; writes kept in $KEEP/$TS"
printf '%s\n' "$LINE"

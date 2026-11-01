#!/usr/bin/env bash
# prefix.sh: make the Wine prefix on the host (the console cannot run wineboot: patch 0550 stops
# process creation) with the fork's host Wine, trim it, select the 32-bit CPU (wowprospero), add
# the test programs (hello.exe, gdi64.exe, ...) and Wine's fonts, and upload it to the console's
# /data/ps4-wine/prefix over FTP.
# From: prospero-win tools/pw_prefix.py @ 0e7b6b4 (LGPL-2.1-or-later): what is stripped from a
# prefix before the upload (dosdevices) and the size verification.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/prefix.sh [--make] [--upload] [--extras] [--dest DIR] [--dry-run]

  --make     WINEPREFIX=build/prefix WINEARCH=wow64 wineboot --init with the host Wine
             (third_party/prospero-win/.deps/wine-host), then: remove dosdevices (Wine recreates
             it on the console; a title cannot make symlinks), keep the DLL/EXE files under
             drive_c/windows/{system32,syswow64} (the PE loader maps a builtin only when its
             file is there), set HKLM\Software\Microsoft\Wow64\x86 to wowprospero.dll (32-bit
             programs on the IA-32 translator, milestone f), build tests/wine_hello64.c with
             x86_64-w64-mingw32-gcc into drive_c/hello.exe, then the extras
  --upload   mirror build/prefix to \$PS4_HOST:$PS4_DATA_ROOT/prefix with lftp, verify sizes
  --extras   into the existing build/prefix: tests/wine_gdi64.c -> drive_c/gdi64.exe (milestone
             d2/d3), tests/wine_vk64.c -> drive_c/vk64.exe (e2/e3), tests/wine_d3d11tri64.c ->
             drive_c/d3d11tri64.exe and DXVK 2.6.2's x64 d3d11.dll and dxgi.dll ->
             drive_c/windows/system32 and its x32 d3d9.dll -> drive_c/windows/syswow64 (milestones
             e and g; the release pinned in the fork's
             tools/pw_install.py, downloaded to build/downloads and checked), Wine's fonts (third_party/prospero-win/.deps/wine-orbis/prx/fonts, from
             build.sh wine) -> drive_c/windows/Fonts (the console lists no /app0 directory, so
             win32u finds fonts only there), with i686-w64-mingw32-gcc tests/wine_hello32.c ->
             drive_c/hello32.exe and tests/wine_wow32.c -> drive_c/wow32.exe (milestone f1/f2) and
             the host build's wowprospero.dll and wow64native.dll (phase p2) -> drive_c/windows/system32, the user's Space Cadet
             Pinball (games/Pinball, gitignored, when present) -> drive_c/Pinball (milestone f),
             tests/wine_vk64.c for i686 -> drive_c/vk32.exe and tests/wine_d3d9tri32.c ->
             drive_c/d3d9tri32.exe with drive_c/g1/dxvk.conf (milestone g1m/g1), the MenuHeight check;
             then put just those files (no mirror of the whole prefix; the CPU key is --make's)
  (no option: --make and --upload)
USAGE
}
MAKE=0; UPLOAD=0; EXTRAS=0; DRY=0; DEST="$PS4_DATA_ROOT/prefix"
while [ $# -gt 0 ]; do
    case "$1" in
        --make) MAKE=1; shift ;;
        --upload) UPLOAD=1; shift ;;
        --extras) EXTRAS=1; shift ;;
        --dest) DEST="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
[ "$MAKE$UPLOAD$EXTRAS" != 000 ] || { MAKE=1; UPLOAD=1; }

PREFIX="$BUILD_DIR/prefix"
WINE="$PROSPERO_WIN_DIR/.deps/wine-host/install/usr/bin/wine"
HELLO_SRC="$PROSPERO_WIN_DIR/tests/wine_hello64.c"
GDI_SRC="$PROSPERO_WIN_DIR/tests/wine_gdi64.c"
VK64_SRC="$PROSPERO_WIN_DIR/tests/wine_vk64.c"
D3D11_SRC="$PROSPERO_WIN_DIR/tests/wine_d3d11tri64.c"
HELLO32_SRC="$PROSPERO_WIN_DIR/tests/wine_hello32.c"
WOW32_SRC="$PROSPERO_WIN_DIR/tests/wine_wow32.c"
D3D9_SRC="$PROSPERO_WIN_DIR/tests/wine_d3d9tri32.c"   # milestone g1: 32-bit D3D9 under DXVK
WINCB_SRC="$PROSPERO_WIN_DIR/tests/wine_wincb.c"   # phase p5 step p5w: windows and callbacks on new threads
WOWP_DLL="$PROSPERO_WIN_DIR/.deps/wine-host/build/dlls/wowprospero/x86_64-windows/wowprospero.dll"
W64N_DLL="$PROSPERO_WIN_DIR/.deps/wow64native/x86_64-windows/wow64native.dll"   # tools/build_wow64native.sh (phase p2)
PINBALL_SRC="$REPO_ROOT/games/Pinball"   # the user's files (docs/ps4/HANDOFF-f.md "Inputs"), never tracked
FONTS_SRC="$PROSPERO_WIN_DIR/.deps/wine-orbis/prx/fonts"
EXTRA_FILES=(drive_c/gdi64.exe drive_c/vk64.exe drive_c/d3d11tri64.exe
    drive_c/windows/system32/d3d11.dll drive_c/windows/system32/dxgi.dll drive_c/windows/syswow64/d3d9.dll
    drive_c/hello32.exe drive_c/wow32.exe drive_c/windows/system32/wowprospero.dll
    drive_c/windows/system32/wow64native.dll drive_c/wincb32.exe drive_c/wincb64.exe
    drive_c/vk32.exe drive_c/d3d9tri32.exe drive_c/g1/dxvk.conf)

# DXVK's 64-bit d3d11.dll and dxgi.dll into system32 (milestone e) and its 32-bit d3d9.dll into
# syswow64 (milestone g), from the release the fork pins (common.sh dxvk_archive). Native only where
# WINEDLLOVERRIDES says so (the title's plan e sets d3d11,dxgi=n, plans g1 and g d3d9=n); other
# programs keep Wine's builtin d3d11 and d3d9.
add_dxvk() {
    local archive
    archive="$(dxvk_archive)"
    tar -xzf "$archive" -C "$PREFIX/drive_c/windows/system32" --strip-components=2 \
        "dxvk-$DXVK_VERSION/x64/d3d11.dll" "dxvk-$DXVK_VERSION/x64/dxgi.dll"
    tar -xzf "$archive" -C "$PREFIX/drive_c/windows/syswow64" --strip-components=2 "dxvk-$DXVK_VERSION/x32/d3d9.dll"
}

# The test programs, the fonts and the registry check; fills EXTRA_FILES.
add_extras() {
    need_cmd x86_64-w64-mingw32-gcc
    x86_64-w64-mingw32-gcc -O1 -o "$PREFIX/drive_c/gdi64.exe" "$GDI_SRC" -lgdi32 -luser32
    # Milestone e2/e3's Vulkan program, against mesa-ps4's Khronos headers (mingw ships none).
    [ -f "$MESA_SRC_DIR/include/vulkan/vulkan.h" ] || die "no Vulkan headers at $MESA_SRC_DIR/include: scripts/ps4/build.sh mesa"
    x86_64-w64-mingw32-gcc -O1 -Wall -Wextra -Werror -idirafter "$MESA_SRC_DIR/include" -o "$PREFIX/drive_c/vk64.exe" \
        "$VK64_SRC" -luser32
    x86_64-w64-mingw32-gcc -O1 -Wall -Wextra -Werror -o "$PREFIX/drive_c/d3d11tri64.exe" "$D3D11_SRC" \
        -ld3d11 -ldxgi -ld3dcompiler_47 -luser32
    add_dxvk
    # Milestone f1/f2: 32-bit programs (their checks, then gdi64.exe's picture built for i686, in
    # wow32.exe: one Wine program per console launch) and the CPU backend they run on, which is a
    # builtin like the others: its file must be in system32.
    need_cmd i686-w64-mingw32-gcc
    i686-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -o "$PREFIX/drive_c/hello32.exe" \
        "$HELLO32_SRC"
    i686-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -o "$PREFIX/drive_c/wow32.exe" \
        "$WOW32_SRC" -lgdi32 -luser32
    # Phase p5 step p5w: windows and callbacks on the main thread and on new threads, 32- and 64-bit
    # (plan p5w runs wincb32.exe; env.txt's PS4WINE_EXE=C:\wincb64.exe the other).
    i686-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -o "$PREFIX/drive_c/wincb32.exe" \
        "$WINCB_SRC" -luser32
    x86_64-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -o "$PREFIX/drive_c/wincb64.exe" \
        "$WINCB_SRC" -luser32
    # Milestone g (docs/ps4/HANDOFF-g.md): g1m's vk32.exe, vk64.exe's source for i686 (32-bit Vulkan
    # through WoW64's placed maps), and g1's d3d9tri32.exe under DXVK's x32 d3d9.dll (add_dxvk) with
    # the three settings of DXVK 2.6.2's built-in vampire.exe profile, which its name does not match,
    # in C:\g1\dxvk.conf (plan g1 sets DXVK_CONFIG_FILE).
    i686-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -idirafter "$MESA_SRC_DIR/include" \
        -o "$PREFIX/drive_c/vk32.exe" "$VK64_SRC" -luser32
    i686-w64-mingw32-gcc -O1 -fno-omit-frame-pointer -Wall -Wextra -Werror -o "$PREFIX/drive_c/d3d9tri32.exe" \
        "$D3D9_SRC" -ld3d9 -luser32
    mkdir -p "$PREFIX/drive_c/g1"
    printf 'd3d9.deferSurfaceCreation = True\nd3d9.memoryTrackTest = True\nd3d9.maxAvailableMemory = 1024\n' \
        > "$PREFIX/drive_c/g1/dxvk.conf"
    [ -f "$WOWP_DLL" ] || die "no $WOWP_DLL: scripts/ps4/build.sh wine"
    command cp -f "$WOWP_DLL" "$PREFIX/drive_c/windows/system32/"
    # Phase p2: the hardware WoW64 backend, selected per run by WINE_PS5_WOW64_CPU (patch 0611); the
    # prefix's CPU key keeps naming wowprospero.dll, the fallback (0614).
    [ -f "$W64N_DLL" ] || die "no $W64N_DLL: scripts/ps4/build.sh wine"
    command cp -f "$W64N_DLL" "$PREFIX/drive_c/windows/system32/"
    # Milestone f: Space Cadet Pinball, the user's loose XP files, as C:\Pinball.
    if [ -f "$PINBALL_SRC/PINBALL.EXE" ]; then
        mkdir -p "$PREFIX/drive_c/Pinball"
        command cp -f "$PINBALL_SRC"/* "$PREFIX/drive_c/Pinball/"
        for f in "$PREFIX"/drive_c/Pinball/*; do EXTRA_FILES+=("drive_c/Pinball/$(basename "$f")"); done
    else
        log "no $PINBALL_SRC/PINBALL.EXE: C:\Pinball left out (milestone f needs it)"
    fi
    ls "$FONTS_SRC"/*.ttf >/dev/null 2>&1 || die "no fonts at $FONTS_SRC: scripts/ps4/build.sh wine"
    mkdir -p "$PREFIX/drive_c/windows/Fonts"
    cp "$FONTS_SRC"/*.ttf "$PREFIX/drive_c/windows/Fonts/"
    for f in "$PREFIX"/drive_c/windows/Fonts/*.ttf; do EXTRA_FILES+=("drive_c/windows/Fonts/$(basename "$f")"); done
    # A font-less wineboot without patch 0410 stored stack garbage as MenuHeight (prospero-win
    # measured 6750319), and every window then had a giant menu bar: refuse an implausible one.
    local menu
    menu="$(sed -n 's/^"MenuHeight"="\([0-9-]*\)"/\1/p' "$PREFIX/user.reg" | head -n1)"
    if [ -n "$menu" ] && { [ "$menu" -lt 0 ] || [ "$menu" -gt 64 ]; }; then
        die "user.reg has MenuHeight=$menu (a font-less wineboot's garbage, patch 0410): remake the prefix"
    fi
    log "extras: gdi64.exe $(stat -c %s "$PREFIX/drive_c/gdi64.exe") bytes, vk64.exe $(stat -c %s "$PREFIX/drive_c/vk64.exe") bytes, d3d11tri64.exe and DXVK $DXVK_VERSION, wow32.exe $(stat -c %s "$PREFIX/drive_c/wow32.exe") bytes and wowprospero.dll, wincb32.exe and wincb64.exe, ${#EXTRA_FILES[@]} files, MenuHeight=${menu:-unset}"
}

# put FILES... (relative to the prefix) and verify their sizes.
put_files() {
    local cmds="set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2;
open ftp://$PS4_HOST:$PS4_FTP_PORT;" dirs="" f bad=0 want have
    for f in "$@"; do
        case " $dirs " in *" $(dirname "$f") "*) ;; *) dirs="$dirs $(dirname "$f")"; cmds="$cmds
mkdir -pf '$DEST/$(dirname "$f")';" ;; esac
        cmds="$cmds
put -O '$DEST/$(dirname "$f")' '$PREFIX/$f';"
    done
    cmds="$cmds
quit"
    if [ "$DRY" = 1 ]; then printf 'lftp -c "%s"\n' "$cmds"; return 0; fi
    lftp -c "$cmds" >&2
    for f in "$@"; do
        want="$(stat -c %s "$PREFIX/$f")"
        have="$(curl -sS --ftp-pasv "ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/$(dirname "$f")/" 2>/dev/null |
            awk -v n="$(basename "$f")" '$NF == n { print $5 }' | head -n1 || true)"
        [ "$have" = "$want" ] || { log "size mismatch: $f local $want remote ${have:-missing}"; bad=$((bad + 1)); }
    done
    [ "$bad" = 0 ] || die "upload incomplete"
    log "put and verified $# file(s) under $DEST"
}

if [ "$MAKE" = 1 ]; then
    [ -x "$WINE" ] || die "no host Wine at $WINE: scripts/ps4/build.sh wine"
    need_cmd x86_64-w64-mingw32-gcc
    rm -rf "$PREFIX"
    log "wineboot --init into $PREFIX (wow64)"
    WINEPREFIX="$PREFIX" WINEARCH=wow64 WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        "$WINE" wineboot --init >/dev/null 2>&1
    WINEPREFIX="$PREFIX" "$WINE"server -w 2>/dev/null || true
    [ -f "$PREFIX/system.reg" ] || die "wineboot left no system.reg"
    # Milestone f: 32-bit programs on wowprospero (the IA-32 translator), named by the prefix's CPU
    # key (Wine's wow64 reads it; WINE_PS5_WOW64_CPU, patch 0611, would override it). Set after
    # wineboot, which runs its 32-bit setup on the default CPU; nothing 32-bit runs on this host
    # Wine afterwards (its install has no wowprospero).
    WINEPREFIX="$PREFIX" WINEDEBUG=-all "$WINE" reg add 'HKLM\Software\Microsoft\Wow64\x86' /ve /d wowprospero.dll /f \
        >/dev/null 2>&1 || die "reg add of the CPU key failed"
    WINEPREFIX="$PREFIX" "$WINE"server -w 2>/dev/null || true
    grep -A3 '^\[Software\\\\Microsoft\\\\Wow64\\\\x86\]' "$PREFIX/system.reg" | grep -q '^@="wowprospero.dll"' ||
        die "system.reg does not name wowprospero.dll as the x86 CPU"
    # A title cannot create symlinks: dosdevices goes (Wine recreates it from the registry).
    rm -rf "$PREFIX/dosdevices"
    # The DLL and EXE files wineboot puts in system32/syswow64 stay: Wine's PE loader maps a
    # builtin only when its file exists there (outside prefix bootstrap mode), so without them
    # the first load fails with "could not load kernel32.dll, status c0000135" (console run 14).
    x86_64-w64-mingw32-gcc -O1 -o "$PREFIX/drive_c/hello.exe" "$HELLO_SRC"
    add_extras
    find "$PREFIX" -type l -delete   # no symlinks reach the console
    log "prefix: $(find "$PREFIX" -type f | wc -l) files, $(du -sh "$PREFIX" | cut -f1); hello.exe $(stat -c %s "$PREFIX/drive_c/hello.exe") bytes"
fi

if [ "$EXTRAS" = 1 ] && [ "$MAKE" = 0 ]; then
    [ -f "$PREFIX/user.reg" ] || die "no prefix at $PREFIX: run with --make"
    add_extras
    [ "$UPLOAD" = 1 ] || { need_cmd lftp; put_files "${EXTRA_FILES[@]}"; }
fi

if [ "$UPLOAD" = 1 ]; then
    [ -d "$PREFIX/drive_c" ] || die "no prefix at $PREFIX: run with --make"
    need_cmd lftp
    CMDS="set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2;
open ftp://$PS4_HOST:$PS4_FTP_PORT;
mkdir -pf '$DEST';
mirror -R --no-perms --parallel=4 --only-newer --ignore-time '$PREFIX' '$DEST';
put -O '$DEST' '$PREFIX/system.reg'; put -O '$DEST' '$PREFIX/user.reg';
put -O '$DEST' '$PREFIX/userdef.reg'; put -O '$DEST' '$PREFIX/.update-timestamp';
quit"
    # The registry files are put explicitly: the console's Wine rewrites them, and mirror's
    # newer-than test (which trusts the console's clock) left a changed user.reg in place once.
    if [ "$DRY" = 1 ]; then printf 'lftp -c "%s"\n' "$CMDS"; exit 0; fi
    log "uploading to ftp://$PS4_HOST:$PS4_FTP_PORT$DEST"
    lftp -c "$CMDS" >&2
    bad=0
    for f in system.reg user.reg userdef.reg drive_c/hello.exe drive_c/gdi64.exe drive_c/wow32.exe \
        drive_c/windows/system32/wowprospero.dll drive_c/windows/system32/wow64native.dll; do
        want="$(stat -c %s "$PREFIX/$f")"
        have="$(curl -sS --ftp-pasv "ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/$(dirname "$f")/" 2>/dev/null |
            awk -v n="$(basename "$f")" '$NF == n { print $5 }' | head -n1 || true)"
        [ "$have" = "$want" ] || { log "size mismatch: $f local $want remote ${have:-missing}"; bad=$((bad + 1)); }
    done
    [ "$bad" = 0 ] || die "upload incomplete"
    log "prefix uploaded and verified"
fi

#!/usr/bin/env bash
# prefix.sh: make the Wine prefix on the host (the console cannot run wineboot: patch 0550 stops
# process creation) with the fork's host Wine, trim it, add hello.exe, and upload it to the
# console's /data/ps4-wine/prefix over FTP.
# From: prospero-win tools/pw_prefix.py @ 0e7b6b4 (LGPL-2.1-or-later): what is stripped from a
# prefix before the upload (dosdevices) and the size verification.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/prefix.sh [--make] [--upload] [--dest DIR] [--dry-run]

  --make     WINEPREFIX=build/prefix WINEARCH=wow64 wineboot --init with the host Wine
             (third_party/prospero-win/.deps/wine-host), then: remove dosdevices (Wine recreates
             it on the console; a title cannot make symlinks), keep the DLL/EXE files under
             drive_c/windows/{system32,syswow64} (the PE loader maps a builtin only when its
             file is there), build tests/wine_hello64.c with x86_64-w64-mingw32-gcc into
             drive_c/hello.exe
  --upload   mirror build/prefix to \$PS4_HOST:$PS4_DATA_ROOT/prefix with lftp, verify sizes
  (no option: both)
USAGE
}
MAKE=0; UPLOAD=0; DRY=0; DEST="$PS4_DATA_ROOT/prefix"
while [ $# -gt 0 ]; do
    case "$1" in
        --make) MAKE=1; shift ;;
        --upload) UPLOAD=1; shift ;;
        --dest) DEST="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
[ "$MAKE$UPLOAD" != 00 ] || { MAKE=1; UPLOAD=1; }

PREFIX="$BUILD_DIR/prefix"
WINE="$PROSPERO_WIN_DIR/.deps/wine-host/install/usr/bin/wine"
HELLO_SRC="$PROSPERO_WIN_DIR/tests/wine_hello64.c"

if [ "$MAKE" = 1 ]; then
    [ -x "$WINE" ] || die "no host Wine at $WINE: scripts/ps4/build.sh wine"
    need_cmd x86_64-w64-mingw32-gcc
    rm -rf "$PREFIX"
    log "wineboot --init into $PREFIX (wow64)"
    WINEPREFIX="$PREFIX" WINEARCH=wow64 WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        "$WINE" wineboot --init >/dev/null 2>&1
    WINEPREFIX="$PREFIX" "$WINE"server -w 2>/dev/null || true
    [ -f "$PREFIX/system.reg" ] || die "wineboot left no system.reg"
    # A title cannot create symlinks: dosdevices goes (Wine recreates it from the registry).
    rm -rf "$PREFIX/dosdevices"
    # The DLL and EXE files wineboot puts in system32/syswow64 stay: Wine's PE loader maps a
    # builtin only when its file exists there (outside prefix bootstrap mode), so without them
    # the first load fails with "could not load kernel32.dll, status c0000135" (console run 14).
    x86_64-w64-mingw32-gcc -O1 -o "$PREFIX/drive_c/hello.exe" "$HELLO_SRC"
    find "$PREFIX" -type l -delete   # no symlinks reach the console
    log "prefix: $(find "$PREFIX" -type f | wc -l) files, $(du -sh "$PREFIX" | cut -f1); hello.exe $(stat -c %s "$PREFIX/drive_c/hello.exe") bytes"
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
    for f in system.reg user.reg userdef.reg drive_c/hello.exe; do
        want="$(stat -c %s "$PREFIX/$f")"
        have="$(curl -sS --ftp-pasv "ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/$(dirname "$f")/" 2>/dev/null |
            awk -v n="$(basename "$f")" '$NF == n { print $5 }' | head -n1 || true)"
        [ "$have" = "$want" ] || { log "size mismatch: $f local $want remote ${have:-missing}"; bad=$((bad + 1)); }
    done
    [ "$bad" = 0 ] || die "upload incomplete"
    log "prefix uploaded and verified"
fi

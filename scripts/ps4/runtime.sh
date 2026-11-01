#!/usr/bin/env bash
# runtime.sh: stage the Wine runtime the title loads (the fork's Orbis PRXs, the host Wine's
# PE modules and NLS files) under build/runtime/win/wine and upload it to the console's
# /data/ps4-wine/runtime over FTP (GoldHEN, port 2121). The package carries only the title; a
# Wine fix is one upload of a PRX, no reinstall (docs/ps4/ARCHITECTURE.md §4.1).
# From: prospero-win tools/package_release.sh @ 0e7b6b4 (LGPL-2.1-or-later): the lib/wine layout
# and the host-wine exclusions.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/runtime.sh [--stage-only] [--prx-only] [--dest DIR] [--dry-run]

Stages build/runtime/win/wine/{lib/wine/{x86_64-unix,x86_64-windows,i386-windows},share/wine/nls}
from the fork's .deps/wine-orbis/prx/sce_module/*.prx and .deps/wine-host/install (plus
wowprospero.dll, the WoW64 CPU backend, from the host build tree: it is not installed), then mirrors
it to \$PS4_HOST:/data/ps4-wine/runtime with lftp and verifies every file's size in the listing
(FTP returns .prx files decrypted, so sizes, not hashes). PRX files get mode 777 (the loader
refuses modules without the execute bit).
  --stage-only   stage, do not upload
  --prx-only     stage and upload lib/wine/x86_64-unix only (the usual bring-up iteration)
  --dest DIR     console directory (default $PS4_DATA_ROOT/runtime)
  --dry-run      print the lftp commands
USAGE
}
STAGE_ONLY=0; PRX_ONLY=0; DRY=0; DEST="$PS4_DATA_ROOT/runtime"
while [ $# -gt 0 ]; do
    case "$1" in
        --stage-only) STAGE_ONLY=1; shift ;;
        --prx-only) PRX_ONLY=1; shift ;;
        --dest) DEST="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

FORK="$PROSPERO_WIN_DIR"
PRX_SRC="$FORK/.deps/wine-orbis/prx/sce_module"
HOST_WINE="$FORK/.deps/wine-host/install/usr"
RUNTIME="$BUILD_DIR/runtime"
WIN="$RUNTIME/win/wine"
[ -d "$PRX_SRC" ] || die "no PRXs at $PRX_SRC: scripts/ps4/build.sh wine"
[ -d "$HOST_WINE/lib/wine/x86_64-windows" ] || die "no host Wine at $HOST_WINE: scripts/ps4/build.sh wine"

# 1. the Orbis Unix side
mkdir -p "$WIN/lib/wine/x86_64-unix"
cp "$PRX_SRC"/*.prx "$WIN/lib/wine/x86_64-unix/"
# win32u.bind.txt: its ntdll import slots, which the d1 title checks one by one.
cp "$PRX_SRC"/*.bind.txt "$WIN/lib/wine/x86_64-unix/" 2>/dev/null || true
# The title's test modules (milestone c's recipe probes, milestone d1's binding modules and their slot tables).
for m in pw_probe_mod pw_probe_tls pw_bind_lib pw_bind_use pw_bind_early pw_bind_data pw_bind_thunk; do
    [ ! -f "$BUILD_DIR/title/$m.prx" ] || cp "$BUILD_DIR/title/$m.prx" "$WIN/lib/wine/x86_64-unix/"
    [ ! -f "$BUILD_DIR/title/$m.bind.txt" ] || cp "$BUILD_DIR/title/$m.bind.txt" "$WIN/lib/wine/x86_64-unix/"
done
chmod 755 "$WIN/lib/wine/x86_64-unix"/*.prx
# 2. the PE side and the NLS files, from the host Wine (desktop-only modules left out)
if [ "$PRX_ONLY" = 0 ]; then
    for arch in x86_64-windows i386-windows; do
        mkdir -p "$WIN/lib/wine/$arch"
        rsync -a --delete --exclude '*.a' --exclude 'winex11.drv*' --exclude 'winegstreamer.dll' \
            --exclude 'wpcap.dll' --exclude 'sane.ds' --exclude 'gphoto2.ds' \
            "$HOST_WINE/lib/wine/$arch/" "$WIN/lib/wine/$arch/"
    done
    # wowprospero.dll (milestone f), after the rsync that would delete it: build_wowprospero.sh puts it
    # in the host build tree, not in the install.
    WOWP="$FORK/.deps/wine-host/build/dlls/wowprospero/x86_64-windows/wowprospero.dll"
    [ -f "$WOWP" ] || die "no $WOWP: scripts/ps4/build.sh wine"
    command cp -f "$WOWP" "$WIN/lib/wine/x86_64-windows/"
    mkdir -p "$WIN/share/wine"
    rsync -a --delete "$HOST_WINE/share/wine/nls/" "$WIN/share/wine/nls/"
fi
log "staged $(find "$WIN" -type f | wc -l) files, $(du -sh "$WIN" | cut -f1) under $RUNTIME"
[ "$STAGE_ONLY" = 0 ] || exit 0

# 3. upload
need_cmd lftp
SRC="$RUNTIME"; SUB=""
if [ "$PRX_ONLY" = 1 ]; then
    # A handful of files that change on every Wine build: put each one
    # (mirror's newer-than test trusts the console's clock, which is wrong).
    SRC="$WIN/lib/wine/x86_64-unix"; SUB="/win/wine/lib/wine/x86_64-unix"
    PUTS=""
    for f in "$SRC"/*.prx "$SRC"/*.bind.txt; do if [ -f "$f" ]; then PUTS="$PUTS put -O '$DEST$SUB' '$f';"; fi; done
    CMDS="set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2;
open ftp://$PS4_HOST:$PS4_FTP_PORT;
mkdir -pf '$DEST$SUB';
$PUTS
chmod -R 777 '$DEST$SUB';
quit"
else
    CMDS="set ftp:passive-mode true; set net:timeout 20; set net:max-retries 2;
open ftp://$PS4_HOST:$PS4_FTP_PORT;
mkdir -pf '$DEST$SUB';
mirror -R --no-perms --parallel=4 --only-newer --ignore-time '$SRC' '$DEST$SUB';
chmod -R 777 '$DEST/win/wine/lib/wine/x86_64-unix';
quit"
fi
if [ "$DRY" = 1 ]; then printf 'lftp -c "%s"\n' "$CMDS"; exit 0; fi
log "uploading to ftp://$PS4_HOST:$PS4_FTP_PORT$DEST$SUB"
lftp -c "$CMDS" >&2
# 4. verify by size: the listing of every directory we uploaded
bad=0; checked=0
while IFS= read -r f; do
    rel="${f#"$SRC/"}"
    want="$(stat -c %s "$f")"
    have="$(curl -sS --ftp-pasv "ftp://$PS4_HOST:$PS4_FTP_PORT$DEST$SUB/$(dirname "$rel")/" 2>/dev/null |
        awk -v n="$(basename "$rel")" '$NF == n { print $5 }' | head -n1 || true)"
    checked=$((checked + 1))
    if [ "$have" != "$want" ]; then log "size mismatch: $rel local $want remote ${have:-missing}"; bad=$((bad + 1)); fi
done < <(find "$SRC" -type f \( -name '*.prx' -o -name '*.bind.txt' -o -path '*/nls/*' -o -name 'ntdll.dll' -o -name 'kernel32.dll' -o -name 'kernelbase.dll' -o -name 'msvcrt.dll' -o -name 'ucrtbase.dll' -o -name 'wowprospero.dll' \))
log "verified $checked file sizes, $bad mismatch(es)"
[ "$bad" = 0 ] || die "upload incomplete"

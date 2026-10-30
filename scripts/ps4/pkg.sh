#!/usr/bin/env bash
# pkg.sh: ELF -> fSELF -> .pkg in the OpenOrbis-samples layout.
#
# From: alechurri/nx-on-orbis package-eden.sh @ 11b2c65 (GPL-3.0-or-later) and
#       OpenOrbis/OpenOrbis-PS4-Toolchain samples/hello_world/Makefile @ 0a1aaf9 (GPL-3.0).
# The layout (paid 0x3800000000000011, default authinfo, sce_module/libc.prx +
# libSceFios2.prx, sce_sys/about/right.sprx, SFO CATEGORY gd, SYSTEM_VER 0) is the
# one nx-on-orbis measured to both boot and receive ~4.4 GiB of direct memory on a
# PS4 Pro (FW 12.02, GoldHEN); other layouts gave 768 MiB or refused to start.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/pkg.sh --elf FILE [options]

  --elf FILE         the linked OpenOrbis ELF (PIE, built against link.x / orbis-tls.ld)
  --name NAME        package base name (default: ELF basename); output dist/NAME-<build_id>.pkg
  --title-id ID      (default $TITLE_ID)     --title "TEXT"  (default "$TITLE_NAME")
  --content-id CID   (default derived from the title id)
  --version V        APP_VER/VERSION (default 01.00)
  --assets DIR       copied into the package as assets/ (mounted at /app0/assets); create-gp4
                     accepts only a few root folders, keep everything under assets/
  --icon FILE        512x512 24-bit PNG without alpha (default: generated solid colour)
  --out DIR          output directory (default dist/)
  --stage DIR        staging directory (default build/pkg/NAME)
  --dry-run          print the tool commands without running them (automatic when tools are missing)
USAGE
}

ELF=""; NAME=""; ASSETS=""; ICON=""; OUT="$DIST_DIR"; STAGE=""; VERSION="01.00"; DRY=0
TID="$TITLE_ID"; TNAME="$TITLE_NAME"; CID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --elf) ELF="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --title-id) TID="$2"; shift 2 ;;
        --title) TNAME="$2"; shift 2 ;;
        --content-id) CID="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --assets) ASSETS="$2"; shift 2 ;;
        --icon) ICON="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --stage) STAGE="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
[ -n "$ELF" ] || { usage; exit 1; }
[ "$DRY" = 1 ] || [ -f "$ELF" ] || die "no such ELF: $ELF"
NAME="${NAME:-$(basename "${ELF%.*}")}"
CID="${CID:-IV0000-${TID}_00-$(printf '%-16s' "${NAME^^}" | tr ' ' '0' | tr -c 'A-Z0-9' '0' | cut -c1-16)}"
STAGE="${STAGE:-$BUILD_DIR/pkg/$NAME}"
BID="${BUILD_ID_OVERRIDE:-$(build_id)}"   # a title built from the fork carries the fork's id (build.sh title)
PKG_BASENAME="$NAME-$BID"

CREATE_FSELF="$(oo_tool create-fself || true)"
CREATE_GP4="$(oo_tool create-gp4 || true)"
PKGTOOL="$(oo_tool PkgTool.Core || true)"
if [ -z "$CREATE_FSELF" ] || [ -z "$CREATE_GP4" ] || [ -z "$PKGTOOL" ]; then
    log "OpenOrbis tools not found under $OO_PS4_TOOLCHAIN/bin/linux: dry run"
    DRY=1; CREATE_FSELF="${CREATE_FSELF:-create-fself}"; CREATE_GP4="${CREATE_GP4:-create-gp4}"; PKGTOOL="${PKGTOOL:-PkgTool.Core}"
fi
SAMPLES="$OO_PS4_TOOLCHAIN/samples/piglet"

run() { if [ "$DRY" = 1 ]; then printf '  %s\n' "$*" >&2; else "$@"; fi; }

log "staging $NAME ($TID, $CID, build $BID) in $STAGE"
run rm -rf "$STAGE"
run mkdir -p "$STAGE/sce_sys/about" "$STAGE/sce_module" "$OUT" "$BUILD_DIR/elf"

# 1. fSELF
run "$CREATE_FSELF" -in="$ELF" -out="$STAGE/$NAME.oelf" --eboot "$STAGE/eboot.bin" --paid 0x3800000000000011
run rm -f "$STAGE/$NAME.oelf"
run cp "$ELF" "$BUILD_DIR/elf/$NAME-$BID.elf"    # the exact ELF, for llvm-symbolizer

# 2. the files that select the samples layout
run cp "$SAMPLES/sce_sys/about/right.sprx" "$STAGE/sce_sys/about/"
run cp "$SAMPLES/sce_module/libc.prx" "$SAMPLES/sce_module/libSceFios2.prx" "$STAGE/sce_module/"

# 3. icon (512x512, 24-bit, no alpha)
if [ -n "$ICON" ]; then run cp "$ICON" "$STAGE/sce_sys/icon0.png"
else run ffmpeg -loglevel error -y -f lavfi -i "color=c=0x1f2a44:s=512x512" -frames:v 1 -pix_fmt rgb24 "$STAGE/sce_sys/icon0.png"; fi

FILES="eboot.bin sce_sys/param.sfo sce_sys/icon0.png sce_sys/about/right.sprx sce_module/libc.prx sce_module/libSceFios2.prx"

# 4. assets
if [ -n "$ASSETS" ]; then
    run mkdir -p "$STAGE/assets"
    run cp -a "$ASSETS/." "$STAGE/assets/"
    if [ "$DRY" = 0 ]; then
        while IFS= read -r f; do FILES="$FILES ${f#"$STAGE/"}"; done < <(find "$STAGE/assets" -type f | sort)
    else FILES="$FILES assets/..."; fi
fi

# 5. param.sfo
SFO="$STAGE/sce_sys/param.sfo"
run pkgtool sfo_new "$SFO" >/dev/null
sfo() { run pkgtool sfo_setentry "$SFO" "$1" --type "$2" --maxsize "$3" --value "$4" >/dev/null; }
sfo APP_TYPE Integer 4 1
sfo APP_VER Utf8 8 "$VERSION"
sfo ATTRIBUTE Integer 4 0
sfo CATEGORY Utf8 4 gd
sfo SYSTEM_VER Integer 4 0
sfo CONTENT_ID Utf8 48 "$CID"
sfo DOWNLOAD_DATA_SIZE Integer 4 0
sfo TITLE Utf8 128 "$TNAME"
sfo TITLE_ID Utf8 12 "$TID"
sfo VERSION Utf8 8 "$VERSION"

# 6. gp4 + pkg
if [ "$DRY" = 1 ]; then
    printf '  (cd %s && %s -out pkg.gp4 --content-id=%s --files "%s")\n' "$STAGE" "$CREATE_GP4" "$CID" "$FILES" >&2
    printf '  (cd %s && %s pkg_build pkg.gp4 %s)\n' "$STAGE" "$PKGTOOL" "$OUT" >&2
    printf '  mv %s/%s.pkg %s/%s.pkg\n' "$OUT" "$CID" "$OUT" "$PKG_BASENAME" >&2
    log "dry run complete"
    exit 0
fi
( cd "$STAGE" && "$CREATE_GP4" -out pkg.gp4 --content-id="$CID" --files "$FILES" >/dev/null )
( cd "$STAGE" && pkgtool pkg_build pkg.gp4 "$OUT" >/dev/null )
[ -f "$OUT/$CID.pkg" ] || die "PkgTool produced no $OUT/$CID.pkg"
mv -f "$OUT/$CID.pkg" "$OUT/$PKG_BASENAME.pkg"
log "wrote $OUT/$PKG_BASENAME.pkg ($(stat -c %s "$OUT/$PKG_BASENAME.pkg") bytes); ELF kept as build/elf/$NAME-$BID.elf"
printf '%s\n' "$OUT/$PKG_BASENAME.pkg"

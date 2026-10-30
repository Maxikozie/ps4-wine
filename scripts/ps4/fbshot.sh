#!/usr/bin/env bash
# fbshot.sh: fetch a title's framebuffer readback (/data/ps4-wine/shot.raw, written by probes/triangle.c)
# over FTP and turn it into a PNG for shot.sh --in / check.sh --fb.
#
# This is the swapchain image the title presented, read back by the GPU: it says what the title
# rendered and in which byte order VideoOut will scan it out. It is NOT the HDMI output (no scaler,
# no display pipeline, no TV path); shot.sh with the capture stick is the only check of that.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/fbshot.sh [--remote PATH] [--size WxH] [--label L] [--out FILE.png] [--keep-raw]
       scripts/ps4/fbshot.sh --raw FILE [--size WxH] [--out FILE.png]

  --remote PATH  file on the console (default $FB_REMOTE), fetched from ftp://$PS4_HOST:$PS4_FTP_PORT
  --raw FILE     convert this local raw dump instead of fetching one
  --size WxH     frame size (default $FB_SIZE); the file must be exactly W*H*4 bytes
  --label L      output logs/<timestamp>-L-fb.png (default L = b)
  --out FILE     write the PNG here instead
  --keep-raw     keep the fetched raw file next to the PNG (default: deleted after conversion)
The bytes are read as R,G,B,A per pixel, which is VideoOut's A8B8G8R8 scan-out order (wsi_orbis.c),
not whatever VkFormat the title chose: a BGRA swapchain therefore shows swapped red and blue here,
as it would on screen. Prints "file=<png>" on success.
Exit: 0 ok, 1 usage, 3 fetch failed / no file, 4 wrong size or conversion failed.
USAGE
}

FB_REMOTE=/data/ps4-wine/shot.raw
FB_SIZE=1920x1080
REMOTE="$FB_REMOTE"; RAW=""; SIZE="$FB_SIZE"; LABEL=b; OUT=""; KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --remote) REMOTE="$2"; shift 2 ;;
        --raw) RAW="$2"; shift 2 ;;
        --size) SIZE="$2"; shift 2 ;;
        --label) LABEL="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --keep-raw) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
[[ "$SIZE" =~ ^[0-9]+x[0-9]+$ ]] || { log "bad --size $SIZE"; exit 1; }
need_cmd ffmpeg
mkdir -p "$LOGS_DIR"
BASE="$LOGS_DIR/$(timestamp)-$LABEL-fb"
OUT="${OUT:-$BASE.png}"

if [ -z "$RAW" ]; then
    need_cmd curl
    RAW="$BASE.raw"
    URL="ftp://$PS4_HOST:$PS4_FTP_PORT$REMOTE"
    if ! curl -sS --ftp-pasv -o "$RAW" "$URL"; then
        rm -f "$RAW"; log "could not fetch $URL (did the title write it? fb= in its PS4WINE line says)"; exit 3
    fi
    [ "$KEEP" = 1 ] || trap 'rm -f "$RAW"' EXIT
    log "fetched $URL -> $RAW"
fi
[ -f "$RAW" ] || { log "no such file: $RAW"; exit 3; }

W="${SIZE%x*}"; H="${SIZE#*x}"
HAVE="$(stat -c %s "$RAW")"; WANT=$(( W * H * 4 ))
[ "$HAVE" = "$WANT" ] || { log "$RAW is $HAVE bytes, a ${SIZE} RGBA frame is $WANT (truncated over FTP, or another size)"; exit 4; }
if ! ffmpeg -loglevel error -y -f rawvideo -pix_fmt rgba -video_size "$SIZE" -i "$RAW" -frames:v 1 "$OUT"; then
    log "conversion of $RAW failed"; exit 4
fi
log "framebuffer readback $SIZE -> $OUT"
printf 'file=%s\n' "$OUT"

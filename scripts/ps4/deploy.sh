#!/usr/bin/env bash
# deploy.sh: send a package to the console over GoldHEN FTP (and optionally ask
# the remote package installer to install it), or send an ELF to BinLoader.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/deploy.sh FILE.pkg [--dest DIR] [--name NAME] [--install] [--dry-run]
       scripts/ps4/deploy.sh FILE.elf [--dry-run]

  FILE.pkg     uploaded in binary mode to ftp://$PS4_HOST:$PS4_FTP_PORT$PS4_PKG_DIR/NAME,
               then the remote size is compared with the local one
  --dest DIR   remote directory (default $PS4_PKG_DIR)
  --name NAME  remote file name (default: the local basename)
  --install    after the upload, POST to GoldHEN's remote package installer
               (http://$PS4_HOST:$PS4_RPI_PORT/api/install); on any failure print how to
               install by hand (GoldHEN > Package Installer > $PS4_PKG_DIR)
  FILE.elf     raw ELF bytes to BinLoader on $PS4_HOST:$PS4_BINLOADER_PORT (enable it in GoldHEN first)
  --dry-run    print what would be done
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
FILE="$1"; shift
DEST="$PS4_PKG_DIR"; NAME=""; INSTALL=0; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --install) INSTALL=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
[ "$DRY" = 1 ] || [ -f "$FILE" ] || die "no such file: $FILE"
NAME="${NAME:-$(basename "$FILE")}"

case "$FILE" in
    *.elf|*.bin)
        log "sending $FILE to BinLoader $PS4_HOST:$PS4_BINLOADER_PORT"
        [ "$DRY" = 1 ] && { echo "  nc -N $PS4_HOST $PS4_BINLOADER_PORT < $FILE"; exit 0; }
        nc -z -w3 "$PS4_HOST" "$PS4_BINLOADER_PORT" || die "BinLoader port $PS4_BINLOADER_PORT closed: enable it in GoldHEN"
        nc -N "$PS4_HOST" "$PS4_BINLOADER_PORT" < "$FILE"
        log "sent $(stat -c %s "$FILE") bytes"
        ;;
    *.pkg)
        URL="ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/$NAME"
        log "uploading $FILE -> $URL"
        if [ "$DRY" = 1 ]; then
            echo "  curl --ftp-pasv --ftp-create-dirs -T $FILE $URL"
            echo "  curl ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/   # verify size of $NAME"
            [ "$INSTALL" = 1 ] && echo "  curl -X POST http://$PS4_HOST:$PS4_RPI_PORT/api/install -d '{\"type\":\"direct\",\"packages\":[\"file://$DEST/$NAME\"]}'"
            exit 0
        fi
        nc -z -w3 "$PS4_HOST" "$PS4_FTP_PORT" || die "FTP port $PS4_FTP_PORT closed on $PS4_HOST"
        curl -sS --ftp-pasv --ftp-create-dirs -T "$FILE" "$URL"
        LOCAL_SIZE="$(stat -c %s "$FILE")"
        REMOTE_SIZE="$(curl -sS "ftp://$PS4_HOST:$PS4_FTP_PORT$DEST/" | awk -v n="$NAME" '$NF == n { print $5 }' | tail -n1)"
        [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] || die "size mismatch after upload: local $LOCAL_SIZE, remote '${REMOTE_SIZE:-none}' (FTP can corrupt large files: retry)"
        log "upload verified: $LOCAL_SIZE bytes at $DEST/$NAME"
        if [ "$INSTALL" = 1 ]; then
            if nc -z -w3 "$PS4_HOST" "$PS4_RPI_PORT" 2>/dev/null && \
               RESP="$(curl -sS --max-time 10 -X POST "http://$PS4_HOST:$PS4_RPI_PORT/api/install" \
                         -H 'Content-Type: application/json' \
                         -d "{\"type\":\"direct\",\"packages\":[\"file://$DEST/$NAME\"]}")" && \
               printf '%s' "$RESP" | grep -q '"status" *: *"success"'; then
                log "remote installer accepted it: $RESP"
            else
                log "remote install not available or refused (${RESP:-no response}); install by hand:"
                log "  PS4: GoldHEN > Package Installer > $DEST > $NAME"
            fi
        else
            log "install by hand: GoldHEN > Package Installer > $DEST > $NAME"
        fi
        ;;
    *) die "unknown file type (expected .pkg or .elf): $FILE" ;;
esac

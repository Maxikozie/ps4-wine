#!/usr/bin/env bash
# deploy.sh: send a package to the console over GoldHEN FTP (and optionally ask
# the remote package installer to install it), or send an ELF to BinLoader.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/deploy.sh FILE.pkg [--dest DIR] [--name NAME] [--dry-run]
       scripts/ps4/deploy.sh FILE.elf [--dry-run]

  FILE.pkg     uploaded in binary mode to ftp://$PS4_HOST:$PS4_FTP_PORT$PS4_PKG_DIR/NAME,
               then the remote size is compared with the local one
  --dest DIR   remote directory (default $PS4_PKG_DIR)
  --name NAME  remote file name (default: the local basename)
  --install    removed (it exited 0 even when the POST failed): use scripts/ps4/ctl.sh install;
               exits 2
  FILE.elf     raw ELF bytes to BinLoader on $PS4_HOST:$PS4_BINLOADER_PORT (enable it in GoldHEN first)
  --dry-run    print what would be done
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
FILE="$1"; shift
DEST="$PS4_PKG_DIR"; NAME=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --install) log "deploy.sh --install is gone: use scripts/ps4/ctl.sh install FILE.pkg"; exit 2 ;;
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
        URL="$(ftp_url "$DEST/$NAME")"
        log "uploading $FILE -> $URL"
        if [ "$DRY" = 1 ]; then
            echo "  curl --ftp-pasv --ftp-create-dirs --max-time $PS4_FTP_MAX_TIME -T $FILE $URL"
            echo "  curl $(ftp_url "$DEST/")   # verify size of $NAME"
            exit 0
        fi
        nc -z -w3 "$PS4_HOST" "$PS4_FTP_PORT" || die "FTP port $PS4_FTP_PORT closed on $PS4_HOST"
        ftp_put "$FILE" "$DEST/$NAME" || die "upload of $NAME failed or its size differs (FTP can corrupt large files: retry)"
        log "upload verified: $(stat -c %s "$FILE") bytes at $DEST/$NAME"
        log "install: scripts/ps4/ctl.sh install $DEST/$NAME, or by hand: GoldHEN > Package Installer > $DEST > $NAME"
        ;;
    *) die "unknown file type (expected .pkg or .elf): $FILE" ;;
esac

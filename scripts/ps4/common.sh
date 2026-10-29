#!/usr/bin/env bash
# Shared settings and helpers for scripts/ps4/*.sh. Source it; do not run it.
# Every value can be overridden from the environment.

# Console
PS4_HOST="${PS4_HOST:-192.168.8.184}"
PS4_FTP_PORT="${PS4_FTP_PORT:-2121}"        # GoldHEN FTP (serves the real root)
PS4_KLOG_PORT="${PS4_KLOG_PORT:-3232}"      # GoldHEN klog, plain TCP stream
PS4_BINLOADER_PORT="${PS4_BINLOADER_PORT:-9090}"
PS4_NETLOG_PORT="${PS4_NETLOG_PORT:-18194}" # our UDP netlog, title -> host
PS4_RPI_PORT="${PS4_RPI_PORT:-12800}"       # GoldHEN remote package installer (HTTP), if enabled
PS4_PKG_DIR="${PS4_PKG_DIR:-/data/pkg}"
PS4_DATA_ROOT="${PS4_DATA_ROOT:-/data/ps4-wine}"

# Title
TITLE_ID="${TITLE_ID:-PSWN00001}"
TITLE_NAME="${TITLE_NAME:-ps4-wine}"
CONTENT_ID="${CONTENT_ID:-IV0000-${TITLE_ID}_00-PS4WINE000000000}"

# Host paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFS_DIR="${REFS_DIR:-$REPO_ROOT/refs}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
LOGS_DIR="${LOGS_DIR:-$REPO_ROOT/logs}"
OO_PS4_TOOLCHAIN="${OO_PS4_TOOLCHAIN:-$HOME/.local/opt/openorbis}"
ORBIS_COMPAT_DIR="${ORBIS_COMPAT_DIR:-$REFS_DIR/orbis-compat}"
ORBIS_KIT_DIR="${ORBIS_KIT_DIR:-$REFS_DIR/orbis-porting-kit}"
MESA_PS4_DIR="${MESA_PS4_DIR:-$REFS_DIR/mesa-ps4}"
PROSPERO_WIN_DIR="${PROSPERO_WIN_DIR:-$REPO_ROOT/third_party/prospero-win}"

# Capture stick: set PS4_CAPTURE_DEV to a /dev/videoN to skip auto-detection.
PS4_CAPTURE_DEV="${PS4_CAPTURE_DEV:-}"
PS4_CAPTURE_EXCLUDE="${PS4_CAPTURE_EXCLUDE:-HP True Vision}"   # the laptop webcam

log()  { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "error: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
need_cmd() { have "$1" || die "missing command: $1"; }

# Short commit of the repo (or the fork when FROM_DIR is given), plus +dirty.
build_id() {
    local dir="${1:-$REPO_ROOT}" id
    id="$(git -C "$dir" rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"
    if [ "$id" != nogit ] && ! git -C "$dir" diff --quiet HEAD -- 2>/dev/null; then id="${id}+dirty"; fi
    printf '%s' "$id"
}

timestamp() { date +%Y%m%d-%H%M%S; }

# OpenOrbis tool lookup: the release asset puts Linux binaries in bin/linux/.
oo_tool() {
    local t="$1"
    for p in "$OO_PS4_TOOLCHAIN/bin/linux/$t" "$OO_PS4_TOOLCHAIN/bin/$t"; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

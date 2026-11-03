#!/usr/bin/env bash
# logs.sh: capture the console's klog (TCP 3232, no history, so start this before
# launching) and our UDP netlog into one time-stamped file under logs/, and
# optionally wait for a line matching a regex.
set -euo pipefail
set +m
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/logs.sh [--label L] [--klog] [--netlog] [--expect REGEX] [--timeout S] [--out FILE] [--quiet]

  --label L       part of the file name: logs/<timestamp>-L.log (default: run)
  --klog          only klog (nc $PS4_HOST $PS4_KLOG_PORT)
  --netlog        only netlog (UDP listener on 0.0.0.0:$PS4_NETLOG_PORT)
                  default: both, merged; each line is prefixed "HH:MM:SS K|N "
  --expect REGEX  exit 0 as soon as a captured line matches (extended regex), printing it
  --timeout S     stop after S seconds (default 0 = run until Ctrl-C, or until --expect matches);
                  with --expect, a timeout exits 1
  --out FILE      write here instead of logs/<timestamp>-L.log
  --quiet         do not echo lines to the terminal
Exit: 0 matched / finished, 1 expect timed out, 2 could not open a source.
USAGE
}

LABEL=run; KLOG=1; NETLOG=1; EXPECT=""; TIMEOUT=0; OUT=""; QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL="$2"; shift 2 ;;
        --klog) KLOG=1; NETLOG=0; shift ;;
        --netlog) NETLOG=1; KLOG=0; shift ;;
        --expect) EXPECT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
mkdir -p "$LOGS_DIR"
OUT="${OUT:-$LOGS_DIR/$(timestamp)-$LABEL.log}"
: > "$OUT"
PIDS=()
kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null || true); do kill_tree "$c"; done; kill "$1" 2>/dev/null || true; }
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && { kill_tree "$p"; wait "$p" 2>/dev/null || true; }; done; }
# INT/TERM must end the script: a trap that only cleaned up left the main loop
# polling forever once its sources were gone (a stale g1n logger, 2026-11-03).
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stamp() { # stamp TAG: prefix each stdin line and append to $OUT (and the terminal)
    local tag="$1" line
    while IFS= read -r line; do
        printf '%s %s %s\n' "$(date +%H:%M:%S)" "$tag" "$line" >> "$OUT"
        [ "$QUIET" = 1 ] || printf '%s %s %s\n' "$(date +%H:%M:%S)" "$tag" "$line"
    done
}

klog_source() { while true; do nc "$PS4_HOST" "$PS4_KLOG_PORT" 2>/dev/null || true; echo "[logs.sh] klog connection closed, reconnecting"; sleep 2; done | stamp K; }
netlog_source() { python3 -u "$SCRIPT_DIR/netlog_recv.py" "$PS4_NETLOG_PORT" | stamp N; }

if [ "$KLOG" = 1 ]; then
    if ! nc -z -w3 "$PS4_HOST" "$PS4_KLOG_PORT" 2>/dev/null; then
        log "klog $PS4_HOST:$PS4_KLOG_PORT unreachable (is klog on in GoldHEN?)"
        [ "$NETLOG" = 1 ] || exit 2
    else
        klog_source &
        PIDS+=("$!")
    fi
fi
if [ "$NETLOG" = 1 ]; then
    netlog_source &
    PIDS+=("$!")
fi

log "capturing to $OUT (klog=$KLOG netlog=$NETLOG timeout=${TIMEOUT}s${EXPECT:+ expect=/$EXPECT/})"
START=$(date +%s)
while true; do
    if [ -n "$EXPECT" ] && grep -qE -- "$EXPECT" "$OUT"; then
        grep -E -m1 -- "$EXPECT" "$OUT"
        exit 0
    fi
    if [ "$TIMEOUT" -gt 0 ] && [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ]; then
        if [ -n "$EXPECT" ]; then log "timeout: no line matched /$EXPECT/ in $OUT"; exit 1; fi
        exit 0
    fi
    sleep 0.5
done

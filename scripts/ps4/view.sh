#!/usr/bin/env bash
# view.sh: live view of the PS4's HDMI output from the capture stick, for the user.
# The video goes to mpv; the sound goes from the stick's PipeWire source straight to the
# speakers through pw-loopback. mpv's own external audio input lagged the picture by ~0.5 s
# (its capture backlog is never drained), so the two paths are kept apart.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/view.sh [--device DEV] [--sink NAME] [--no-audio] [--latency MS]

  --device DEV   capture node (default PS4_CAPTURE_DEV, else $DEFAULT_DEV)
  --sink NAME    PipeWire sink for the sound (default PS4_AUDIO_SINK, else the default sink;
                 pactl list sinks short lists them)
  --no-audio     video only
  --latency MS   pw-loopback latency (default $LATENCY)
Keys in mpv: f fullscreen, space pause, s screenshot (PNG into logs/), q quit.
Only one program can read the stick: quit this before shot.sh or check.sh captures.
Exit: mpv's, or 3 when the capture device does not exist.
USAGE
}

DEFAULT_DEV=/dev/v4l/by-id/usb-MACROSILICON_2109-video-index0
DEV="${PS4_CAPTURE_DEV:-$DEFAULT_DEV}"; SINK="${PS4_AUDIO_SINK:-}"; AUDIO=1; LATENCY=20
while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEV="$2"; shift 2 ;;
        --sink) SINK="$2"; shift 2 ;;
        --no-audio) AUDIO=0; shift ;;
        --latency) LATENCY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

need_cmd mpv
[ -e "$DEV" ] || { log "capture device $DEV does not exist; plug in the HDMI stick or pass --device"; exit 3; }

LOOP_PID=""
cleanup() { [ -n "$LOOP_PID" ] && kill "$LOOP_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

if [ "$AUDIO" = 1 ]; then
    SOURCE="$(pactl list sources short 2>/dev/null | awk '$2 ~ /MACROSILICON_2109/ && $2 !~ /\.monitor$/ { print $2; exit }')"
    if [ -n "$SOURCE" ] && command -v pw-loopback >/dev/null; then
        pw-loopback -n ps4-capture-audio -C "$SOURCE" ${SINK:+-P "$SINK"} -l "$LATENCY" >/dev/null 2>&1 &
        LOOP_PID=$!
    else
        log "no PipeWire source for the stick (or no pw-loopback): video only"
    fi
fi

mkdir -p "$LOGS_DIR"
mpv "av://v4l2:$DEV" \
    --demuxer-lavf-o=video_size=1920x1080,input_format=mjpeg,framerate=60 \
    --profile=low-latency --untimed --no-audio --title=PS4 \
    --screenshot-format=png --screenshot-directory="$LOGS_DIR"

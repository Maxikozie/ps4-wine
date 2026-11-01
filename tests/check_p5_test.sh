#!/usr/bin/env bash
# check_p5_test.sh: run scripts/ps4/check.sh p5 against fixture logs and generated WAVs, and compare verdicts.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_p5_test.sh

Runs scripts/ps4/check.sh p5 on each tests/fixtures/p5-*.log (synthetic: written before the first p5 launch,
docs/ps4/HANDOFF-p.md) with generated 48 kHz stereo WAVs for the HDMI audio rule (a tone at -12 dBFS in the
tail's window passes; noise at the stick's silent level, about -37 dB mean, fails). Also: no non-silent grain,
the port refused (0x809b0001), underruns, missed vblanks on p4's path, an audio-off launch, and the options p5
requires (--audio with --audio-window, or --no-audio). Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# 20 s of noise at about the stick's silent level (-37 dB mean), and the same with a tone of about
# -12 dB RMS from 8 s to 14 s (ffmpeg's sine is 1/8 full scale, -21 dB RMS: +9 dB).
ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=d=20:c=pink:a=0.1:r=48000" -ac 2 "$TMP/quiet.wav"
ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=d=20:c=pink:a=0.1:r=48000" -f lavfi -i "sine=f=660:d=6:r=48000" \
    -filter_complex "[1]volume=9dB,adelay=8000|8000,apad=whole_dur=20[t];[0][t]amix=inputs=2:normalize=0" \
    -ac 2 "$TMP/loud.wav"

# case <fixture> <expected exit> <expected verdict> <substring of the output or ""> [check.sh options...]
case_() {
    local fx="$1" want_rc="$2" want="$3" sub="$4" out rc=0
    shift 4
    out="$("$ROOT/scripts/ps4/check.sh" p5 --log "$FIX/$fx" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL p5 %s %s: exit %s (want %s): %s\n' "$fx" "$*" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   p5 %s %s: %s\n' "$fx" "$*" "${want:-exit $rc}"
    fi
}

case_ p5-pass.log      0 PASS  "HDMI audio mean" --audio "$TMP/loud.wav" --audio-window 8:6
case_ p5-pass.log      1 FAIL  "< -30 dB" --audio "$TMP/quiet.wav" --audio-window 8:6
case_ p5-pass.log      0 "PASS (no audio)" "" --no-audio
case_ p5-pass.log      1 ""    "give --audio WAV"
case_ p5-nosound.log   1 FAIL  "grains_nonzero=0 < 10" --no-audio
case_ p5-openfail.log  1 FAIL  "audio_open=err:0x809b0001 != ok" --no-audio
case_ p5-underrun.log  1 FAIL  "underruns=3 != 0" --no-audio
case_ p5-missed.log    1 FAIL  "shown_hz=54.2 < 59" --no-audio
case_ p5-off.log       1 FAIL  "audio_open=- != ok" --no-audio

if [ "$fails" -ne 0 ]; then echo "check_p5_test: $fails failure(s)"; exit 1; fi
echo "check_p5_test: all passed"

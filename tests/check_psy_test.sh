#!/usr/bin/env bash
# check_psy_test.sh: run scripts/ps4/check.sh's Psychonauts rules (j, k, later l-n) against fixture logs.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/check_psy_test.sh

Runs scripts/ps4/check.sh j on tests/fixtures/j-*.log (synthetic: written 2026-11-02 before the first j run,
docs/ps4/HANDOFF-i.md). j is the host's line from host-game.sh --game psychonauts: it passes ("PASS (host)")
with the EXE at 0x00400000, no missing DLL, 41200 presents, a new save, the pad read and 725 s; it fails with
the EXE moved to 0x00410000, with a missing DLL, with 3100 presents, after 431 s, without a new save and
without a pad read; a log whose game crashed before host-game.sh wrote the line is CRASH. host-game.sh --parse
reads the fields from Wine's output: with every game DLL loaded and only Wine's Indeo codec missing
winegstreamer, dll_missing=0 and dll_missing_wine=1 (the user's choice, 2026-11-02, after the smoke run); a
missing import of the EXE and of binkw32 plus OpenAL32 never loaded is dll_missing=3; in a +keyboard trace,
three MapVirtualKeyEx calls above 0xff of which one reached winex11 with a nonzero answer (winex11's own
GetKeyNameText call and a plain scan code not counted) is mapvk_high=3/1.
Then check.sh k on tests/fixtures/k-*.log (synthetic: written 2026-11-03 before the first k launch) with
generated 48 kHz stereo WAVs as in check_p5_test.sh (a tone at about -12 dB in the window 8:6 passes, noise at
the stick's silent level, about -37 dB mean, fails): Psychonauts' menu at the first mark passes with the loud
WAV, fails with the quiet one, is "PASS (no audio)" with --no-audio and refused without an audio option; it
fails without the mark (menu=0, exit=crash), with the EXE at 0x10000000, with the eboot kept
(eboot_release=off), with audio=fail, with 3 non-silent grains, with 2 audio errors and with an unresolved
fault; stage records without a line are NOLOG naming them, and with an exception CRASH naming them.
Then check.sh l on tests/fixtures/l-*.log (synthetic: written 2026-11-03 before the first l launch): the DS4 as
XInput controller 0 passes with input=xinput, the pad connected at start, the game's read (pad_reads=1), kbm=0,
no unresolved fault and exit=running; it fails with pad_reads=0 (stop point S5) and with pad_reads=- (no
look-up), with 2 keyboard or mouse events, with the pad not connected at start, in keyboard mode, without the
mark (exit=fault) and with an unresolved fault; stage records without a line are NOLOG. The fixtures for m and
n join these before their first launches.
Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# check_p5_test.sh's WAVs: 20 s of noise at about the stick's silent level (-37 dB mean), and the same with a
# tone of about -12 dB RMS from 8 s to 14 s (ffmpeg's sine is 1/8 full scale, -21 dB RMS: +9 dB).
ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=d=20:c=pink:a=0.1:r=48000" -ac 2 "$TMP/quiet.wav"
ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=d=20:c=pink:a=0.1:r=48000" -f lavfi -i "sine=f=660:d=6:r=48000" \
    -filter_complex "[1]volume=9dB,adelay=8000|8000,apad=whole_dur=20[t];[0][t]amix=inputs=2:normalize=0" \
    -ac 2 "$TMP/loud.wav"

# case_ <ms> <fixture> <expected exit> <expected verdict> <substring of the output or ""> [extra args]
case_() {
    local ms="$1" fx="$2" want_rc="$3" want="$4" sub="$5" out rc=0
    shift 5
    out="$("$ROOT/scripts/ps4/check.sh" "$ms" --log "$FIX/$fx" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ] || [[ -n "$want" && "$out" != *"| $want |"* ]] || [[ -n "$sub" && "$out" != *"$sub"* ]]; then
        printf 'FAIL %s %s: exit %s (want %s): %s\n' "$ms" "$fx" "$rc" "$want_rc" "$out"
        fails=$((fails + 1))
    else
        printf 'ok   %s %s: %s\n' "$ms" "$fx" "$want"
    fi
}

case_ j j-pass.log         0 "PASS (host)" "pad_reads=40890"
case_ j j-base-moved.log   1 FAIL  "exe_base=0x00410000 != 0x00400000"
case_ j j-dll-missing.log  1 FAIL  "dll_missing=1 != 0"
case_ j j-fewpresents.log  1 FAIL  "presents=3100 < 3600"
case_ j j-short.log        1 FAIL  "session_s=431 < 600"
case_ j j-nosave.log       1 FAIL  "save_new=0 != 1"
case_ j j-nopad.log        1 FAIL  "pad_reads=0 < 1"
case_ j j-crash.log        1 CRASH "Unhandled page fault"

case_ k k-pass.log         0 PASS  "HDMI audio mean" --audio "$TMP/loud.wav" --audio-window 8:6
case_ k k-pass.log         1 FAIL  "dB < -30 dB" --audio "$TMP/quiet.wav" --audio-window 8:6
case_ k k-pass.log         0 "PASS (no audio)" "menu_s=48" --no-audio
case_ k k-pass.log         1 ""    "k: give --audio WAV --audio-window S:D"
case_ k k-crashed.log      1 FAIL  "menu=0 != 1 exit=crash != running" --no-audio
case_ k k-base-moved.log   1 FAIL  "exe_base=0x10000000 != 0x00400000" --no-audio
case_ k k-keep.log         1 FAIL  "eboot_release=off != ok" --no-audio
case_ k k-audiofail.log    1 FAIL  "audio=fail != on" --no-audio
case_ k k-fewgrains.log    1 FAIL  "grains_nonzero=3 < 10" --no-audio
case_ k k-audioerr.log     1 FAIL  "audio_errors=2 != 0" --no-audio
case_ k k-unresolved.log   1 FAIL  "faults_unresolved=1 != 0" --no-audio
case_ k k-stagesonly.log   1 NOLOG "no 'PS4WINE k' line in k-stagesonly.log; stage records: cpu_probe,wow_bind,display" --no-audio
case_ k k-crash.log        1 CRASH "stage records: cpu_probe,wow_bind,display,audio,psychonauts" --no-audio

case_ l l-pass.log         0 PASS  "pad_reads=1"
case_ l l-noreads.log      1 FAIL  "pad_reads=0 < 1"
case_ l l-nolookup.log     1 FAIL  "pad_reads=- < 1"
case_ l l-kbm.log          1 FAIL  "kbm=2 != 0"
case_ l l-notconnected.log 1 FAIL  "pad_connected_at_start=0 != 1"
case_ l l-keyboard.log     1 FAIL  "input=keyboard != xinput"
case_ l l-crashed.log      1 FAIL  "exit=fault != running"
case_ l l-unresolved.log   1 FAIL  "faults_unresolved=1 != 0"
case_ l l-stagesonly.log   1 NOLOG "no 'PS4WINE l' line in l-stagesonly.log; stage records: cpu_probe,wow_bind,display,audio,xinput"

# parse_ <fixture> <session seconds> <expected output of host-game.sh --parse>
parse_() {
    local fx="$1" secs="$2" want="$3" out rc=0
    out="$("$ROOT/scripts/ps4/host-game.sh" --game psychonauts --parse "$FIX/$fx" --session-s "$secs" 2>&1)" || rc=$?
    if [ "$rc" != 0 ] || [ "$out" != "$want" ]; then
        printf 'FAIL parse %s: exit %s\n  got  %s\n  want %s\n' "$fx" "$rc" "$out" "$want"
        fails=$((fails + 1))
    else
        printf 'ok   parse %s\n' "$fx"
    fi
}

parse_ j-parse-codec.log 600 "exe_base=0x00400000 dll_missing=0 dll_missing_wine=1 dll_absent=- presents=3601 fps_avg=6.0 crossings_per_frame=25 pad_reads=38 pad_calls=40 pad_first_read_ms=232 rumble_events=2 rumble=ok marks=1 dxvk_conf=found steam_init=- mapvk_high=-"
parse_ j-parse-gamemiss.log 0 "exe_base=0x00410000 dll_missing=3 dll_missing_wine=0 dll_absent=binkw32,openal32 presents=1 fps_avg=- crossings_per_frame=- pad_reads=- pad_calls=- pad_first_read_ms=- rumble_events=- rumble=- marks=- dxvk_conf=- steam_init=- mapvk_high=-"
parse_ j-parse-mapvk.log 0 "exe_base=0x00400000 dll_missing=17 dll_missing_wine=0 dll_absent=dinput8,d3d9,d3dx9_40,winmm,dsound,binkw32,isactwin,audiodrv,xinput1_3,steam_api,kernel32,user32,shell32,ole32,oleaut32,msvcr90,openal32 presents=- fps_avg=- crossings_per_frame=- pad_reads=- pad_calls=- pad_first_read_ms=- rumble_events=- rumble=- marks=- dxvk_conf=- steam_init=- mapvk_high=3/1"

if [ "$fails" -eq 0 ]; then echo "check_psy_test: all passed"; else echo "check_psy_test: $fails failure(s)"; exit 1; fi

#!/usr/bin/env bash
# ctl.sh: close, install and launch PSWN00001 with no hands (docs/ps4/HANDOFF-loop.md, phase 1).
# Each command is a 4 KiB block (ctl/ctl_cmd.h) patched into a copy of the ctl ELF, which goes to
# GoldHEN's BinLoader; the ctl's step lines come back over netlog (a running logs.sh) and in
# /data/ps4-wine/ctl/<nonce>.txt (FTP).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/ctl.sh [options] status [PKG]
       scripts/ps4/ctl.sh [options] kill
       scripts/ps4/ctl.sh [options] install PKG
       scripts/ps4/ctl.sh [options] launch [ARG...]
       scripts/ps4/ctl.sh [options] cycle PKG [ARG...]
       scripts/ps4/ctl.sh [options] probe PKG [ARG...]        (console run x1)
       scripts/ps4/ctl.sh judge --log FILE --dialog 0|1 --shot FILE
       scripts/ps4/ctl.sh --print-layout

  status        the ctl's hello, its libraries, the big app, AppExists (and PKG's title ID): no change
  kill          close PSWN00001: only with a proof that the big app is PSWN00001 and none against, and
                never when the ctl's own pid (or app ID) is the title's
  install PKG   install PSWN00001's package (never while it runs); PKG is a local .pkg, uploaded first
                to $PS4_PKG_DIR/<name> and checked by size, or a console path under /data
  launch ARG..  launch PSWN00001 with these arguments (at most 8, 63 bytes each)
  cycle PKG     kill if running, install, launch
  probe PKG     x1: cycle with every diagnostic, then waits for the relaunched title's
                "PW_MS pkg_stamp=" line and appends "PS4WINE x1 ctl ..." to the log (needs --log);
                dialog=unjudged until "judge" records what the shot shows
  judge         append the x1 line again with dialog=0|1 and the shot it was judged from
  --print-layout  the command block's offsets, for tests/ctl_test.sh

Options (anywhere; an unknown -x after the command is a launch argument):
  --log FILE        the running logs.sh capture to read the step lines from (default: FTP only)
  --form F          self (create-fself --eboot of dist/ctl-<id>.elf), elf (dist/ctl-plain-<id>.elf) or
                    auto (default: the form cached in build/ctl/form, else a status in each form, self
                    first, and the first that says hello is cached)
  --elf FILE        the fSELF form's ELF (default: newest dist/ctl-*.elf)
  --plain FILE      the plain form's ELF (default: newest dist/ctl-plain-*.elf)
  --title-pid N     the title's pid (default: the newest "PW_MS pkg_stamp= ... pid=N" in --log, else 0)
  --console-dry     the ctl logs every decision and changes nothing on the console
  --timeout S       wait at most S seconds for the done line (default per command)
  --hello-timeout S wait at most S seconds for the hello line (default 20)
  --patch-only OUT  write the patched file to OUT and stop (no send)
  --dry-run         print the block and the commands, send nothing
Test hooks (tests/ctl_test.sh): CTL_SEND_CMD runs "\$CTL_SEND_CMD FILE" instead of nc (no port check);
CTL_CREATE_FSELF replaces create-fself; CTL_STAMP_TIMEOUT (default 120 s) bounds probe's wait for the stamp; PS4_FTP_BASE=file://DIR stands for the console's FTP root.
Exit: 0 ok, 1 usage or internal error, 2 refused (by the ctl's safety or by ctl.sh), 3 timeout,
      4 console unreachable (BinLoader $PS4_BINLOADER_PORT closed: enable it in GoldHEN), 5 a console call failed.
USAGE
}

# The block's layout (ctl/ctl_cmd.h); tests/ctl_test.sh checks these against the header.
MAGIC=PS4WINE-CTL-CMD1
BLOCK_SIZE=4096; OFF_VERSION=16; OFF_OP=20; OFF_TITLE_PID=24; OFF_FLAGS=28; OFF_NONCE=32; OFF_PKG=72
OFF_ARGC=328; OFF_ARGS=332; NONCE_MAX=40; PATH_MAX=256; ARGS_MAX=8; ARG_LEN=64; VERSION=1
declare -A OPS=([status]=1 [kill]=2 [install]=3 [launch]=4 [cycle]=5 [probe]=6)

LOGF=""; FORM=auto; ELF=""; PLAIN=""; TITLE_PID=""; CONSOLE_DRY=0; TIMEOUT=""; HELLO_TIMEOUT=20; PATCH_ONLY=""; DRY=0
DIALOG=""; SHOT=""
POS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOGF="$2"; shift 2 ;;
        --form) FORM="$2"; shift 2 ;;
        --elf) ELF="$2"; shift 2 ;;
        --plain) PLAIN="$2"; shift 2 ;;
        --title-pid) TITLE_PID="$2"; shift 2 ;;
        --console-dry) CONSOLE_DRY=1; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --hello-timeout) HELLO_TIMEOUT="$2"; shift 2 ;;
        --patch-only) PATCH_ONLY="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --dialog) DIALOG="$2"; shift 2 ;;
        --shot) SHOT="$2"; shift 2 ;;
        --print-layout)
            printf 'magic=%s size=%d version=%d op=%d title_pid=%d flags=%d nonce=%d pkg=%d argc=%d args=%d nonce_max=%d path_max=%d args_max=%d arg_len=%d\n' \
                "$MAGIC" "$BLOCK_SIZE" "$OFF_VERSION" "$OFF_OP" "$OFF_TITLE_PID" "$OFF_FLAGS" "$OFF_NONCE" "$OFF_PKG" \
                "$OFF_ARGC" "$OFF_ARGS" "$NONCE_MAX" "$PATH_MAX" "$ARGS_MAX" "$ARG_LEN"
            exit 0 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; POS+=("$@"); break ;;
        -*) [ "${#POS[@]}" -gt 0 ] && { POS+=("$1"); shift; continue; }; usage; exit 1 ;;
        *) POS+=("$1"); shift ;;
    esac
done
[ "${#POS[@]}" -ge 1 ] || { usage; exit 1; }
CMD="${POS[0]}"; ARGS=("${POS[@]:1}")
case "$FORM" in self|elf|auto) ;; *) die "--form must be self, elf or auto" ;; esac

# ------------------------------------------------------------------ judge
if [ "$CMD" = judge ]; then
    [ -n "$LOGF" ] && [ -f "$LOGF" ] || die "judge: give --log FILE (the x1 run's capture)"
    case "$DIALOG" in 0|1) ;; *) die "judge: give --dialog 0 or 1" ;; esac
    [ -n "$SHOT" ] && [ -f "$SHOT" ] || die "judge: give --shot FILE (the frame the judgement was made from)"
    last="$(grep -E 'PS4WINE x1 ctl ' "$LOGF" | tail -n1 | sed -E 's/^[0-9:]+ [KNH] //')"
    [ -n "$last" ] || die "judge: no 'PS4WINE x1 ctl' line in $LOGF"
    line="$(printf '%s' "$last" | sed -E "s/ dialog=[^ ]*/ dialog=$DIALOG/; s/ dialog_by=[^ ]*//; s/ shot=[^ ]*//") dialog_by=eye shot=$(basename "$SHOT")"
    printf '%s H %s\n' "$(date +%H:%M:%S)" "$line" >> "$LOGF"
    printf '%s\n' "$line"
    exit 0
fi

[ -n "${OPS[$CMD]:-}" ] || { usage; exit 1; }
OP="${OPS[$CMD]}"

# ------------------------------------------------------------------ arguments
PKG_LOCAL=""; PKG_REMOTE=""; LAUNCH_ARGS=()
case "$CMD" in
    install|cycle|probe)
        [ "${#ARGS[@]}" -ge 1 ] || die "$CMD needs PKG"
        PKG="${ARGS[0]}"; LAUNCH_ARGS=("${ARGS[@]:1}") ;;
    status) PKG="${ARGS[0]:-}"; [ "${#ARGS[@]}" -le 1 ] || die "status takes at most PKG" ;;
    launch) PKG=""; LAUNCH_ARGS=("${ARGS[@]}") ;;
    kill) PKG=""; [ "${#ARGS[@]}" = 0 ] || die "kill takes no arguments" ;;
esac
if [ "$CMD" = probe ] && [ "${#LAUNCH_ARGS[@]}" = 0 ]; then LAUNCH_ARGS=(--ctl-x1); fi
if [ -n "$PKG" ]; then
    case "$PKG" in
        /data/*) PKG_REMOTE="$PKG" ;;
        *.pkg) PKG_LOCAL="$PKG"; PKG_REMOTE="$PS4_PKG_DIR/$(basename "$PKG")"
               [ "$DRY" = 1 ] || [ -n "$PATCH_ONLY" ] || [ -f "$PKG_LOCAL" ] || die "no such package: $PKG_LOCAL" ;;
        *) die "PKG must be a local .pkg or a console path under /data: $PKG" ;;
    esac
    [[ "$PKG_REMOTE" =~ ^/data/[A-Za-z0-9._+/-]+$ ]] || die "console path has characters the ctl does not take: $PKG_REMOTE"
    [ "${#PKG_REMOTE}" -lt "$PATH_MAX" ] || die "console path is $((${#PKG_REMOTE})) bytes (at most $((PATH_MAX - 1)))"
fi
[ "${#LAUNCH_ARGS[@]}" -le "$ARGS_MAX" ] || die "at most $ARGS_MAX launch arguments"
for a in "${LAUNCH_ARGS[@]}"; do
    [ "${#a}" -lt "$ARG_LEN" ] || die "launch argument is ${#a} bytes (at most $((ARG_LEN - 1))): $a"
    [[ "$a" =~ ^[[:print:]]+$ ]] || die "launch argument with a non-printable byte: $a"
done
if [ -z "$TITLE_PID" ]; then
    TITLE_PID=0
    if [ -n "$LOGF" ] && [ -f "$LOGF" ]; then
        p="$(grep -oE 'PW_MS pkg_stamp=[^ ]* argv=[^ ]* pid=[0-9]+' "$LOGF" | tail -n1 | sed -E 's/.* pid=//' || true)"
        TITLE_PID="${p:-0}"
    fi
fi
[[ "$TITLE_PID" =~ ^[0-9]+$ ]] || die "--title-pid must be a number"
if [ -z "$TIMEOUT" ]; then
    case "$CMD" in status|kill|launch) TIMEOUT=90 ;; install) TIMEOUT=420 ;; *) TIMEOUT=600 ;; esac
fi

# ------------------------------------------------------------------ the block
# le32 N: the escape text of N's four little-endian bytes (putb's printf turns it into bytes; a command
# substitution of the bytes themselves would drop the NULs)
le32() { local v=$(( $1 & 0xffffffff )); printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((v & 255)) $(((v >> 8) & 255)) $(((v >> 16) & 255)) $(((v >> 24) & 255)); }
# put FILE OFFSET TEXT: TEXT at OFFSET of a block file (NULs around it are already there)
put() { printf '%s' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }
putb() { printf "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }

make_block() { # make_block OUT NONCE OP
    local out="$1" nonce="$2" op="$3" i=0 flags=0
    [ "$CONSOLE_DRY" = 1 ] && flags=1
    head -c "$BLOCK_SIZE" /dev/zero > "$out"
    put "$out" 0 "$MAGIC"
    putb "$out" "$OFF_VERSION" "$(le32 "$VERSION")"
    putb "$out" "$OFF_OP" "$(le32 "$op")"
    putb "$out" "$OFF_TITLE_PID" "$(le32 "$TITLE_PID")"
    putb "$out" "$OFF_FLAGS" "$(le32 "$flags")"
    put "$out" "$OFF_NONCE" "$nonce"
    [ -n "$PKG_REMOTE" ] && put "$out" "$OFF_PKG" "$PKG_REMOTE"
    putb "$out" "$OFF_ARGC" "$(le32 "${#LAUNCH_ARGS[@]}")"
    for a in "${LAUNCH_ARGS[@]}"; do put "$out" $((OFF_ARGS + i * ARG_LEN)) "$a"; i=$((i + 1)); done
    [ "$(stat -c %s "$out")" = "$BLOCK_SIZE" ] || die "block is $(stat -c %s "$out") bytes"
}

# patch_block SRC OUT BLOCK: OUT = SRC with BLOCK over the single magic's block.
patch_block() {
    local src="$1" out="$2" block="$3" offs n
    offs="$(LC_ALL=C grep -obUaF "$MAGIC" "$src" | cut -d: -f1 || true)"
    n="$(printf '%s' "$offs" | grep -c . || true)"
    [ "$n" = 1 ] || { log "$src holds $n copies of the block's magic (want exactly 1)"; return 2; }
    command cp -f "$src" "$out"
    dd if="$block" of="$out" bs=1 seek="$offs" conv=notrunc status=none
}

new_nonce() { printf '%s-%s' "$(date +%Y%m%d%H%M%S)" "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; }

pick_elf() { # pick_elf self|elf
    local f
    if [ "$1" = self ]; then f="${ELF:-$(ls -t "$DIST_DIR"/ctl-*.elf 2>/dev/null | grep -v '/ctl-plain-' | head -n1 || true)}"
    else f="${PLAIN:-$(ls -t "$DIST_DIR"/ctl-plain-*.elf 2>/dev/null | head -n1 || true)}"; fi
    [ -n "$f" ] && [ -f "$f" ] || die "no $1-form ctl ELF (scripts/ps4/build.sh ctl)"
    printf '%s' "$f"
}

WORK="$BUILD_DIR/ctl/send"; mkdir -p "$WORK"
# payload FORM NONCE OP: prints the path of the file to send
payload() {
    local form="$1" nonce="$2" op="$3" src block="$WORK/$2.block" out
    src="$(pick_elf "$form")"
    make_block "$block" "$nonce" "$op"
    if [ "$form" = self ]; then
        out="$WORK/$nonce.elf"
        patch_block "$src" "$out" "$block" || exit 2
        local fself="${CTL_CREATE_FSELF:-}"
        [ -n "$fself" ] || fself="$(oo_tool create-fself)" || die "create-fself not found under $OO_PS4_TOOLCHAIN"
        ( cd "$WORK" && "$fself" -in="$nonce.elf" -out="$nonce.oelf" --eboot "$nonce.bin" --paid 0x3800000000000011 >/dev/null ) ||
            die "create-fself failed on $out"
        rm -f "$WORK/$nonce.oelf"
        out="$WORK/$nonce.bin"
        [ "$(LC_ALL=C grep -c -obUaF "$MAGIC" "$out" || true)" = 1 ] || die "the fSELF lost the block"
    else
        out="$WORK/$nonce.elf"
        patch_block "$src" "$out" "$block" || exit 2
    fi
    printf '%s' "$out"
}

# ------------------------------------------------------------------ results
# lines NONCE: every "PS4CTL NONCE ..." line seen so far (the log, then the result file over FTP)
lines() {
    local nonce="$1"
    { [ -n "$LOGF" ] && [ -f "$LOGF" ] && grep -aF "PS4CTL $nonce " "$LOGF" | sed -E 's/^[0-9:]+ [KNH] //; s/^<[0-9]+>\[[^]]*\] *//'
      [ -f "$WORK/$nonce.txt" ] && cat "$WORK/$nonce.txt"; } 2>/dev/null | grep -aoE "PS4CTL $nonce .*" | awk '!seen[$0]++' || true
}
fetch_result() {
    [ "$DRY" = 0 ] || return 0
    if ftp_get "$PS4_DATA_ROOT/ctl/$1.txt" "$WORK/$1.txt.part" 2>/dev/null; then mv -f "$WORK/$1.txt.part" "$WORK/$1.txt"; fi
    rm -f "$WORK/$1.txt.part"
}
# wait_for NONCE REGEX SECONDS: 0 when a line matches
wait_for() {
    local nonce="$1" re="$2" secs="$3" start=$SECONDS polls=0
    while [ $((SECONDS - start)) -lt "$secs" ]; do
        lines "$nonce" | grep -qE "$re" && return 0
        # The result file is fetched every 3 s without a log, every 15 s with one (netlog may drop lines).
        if [ -z "$LOGF" ] || [ $((polls % 30)) = 29 ]; then
            fetch_result "$nonce"
            lines "$nonce" | grep -qE "$re" && return 0
        fi
        polls=$((polls + 1))
        if [ -z "$LOGF" ]; then sleep 3; else sleep 0.5; fi
    done
    fetch_result "$nonce"
    lines "$nonce" | grep -qE "$re"
}
kv() { printf '%s' "$2" | grep -oE "(^| )$1=[^ ]*" | head -n1 | sed -E "s/^ ?$1=//"; }

send() { # send FILE
    if [ "$DRY" = 1 ]; then echo "  nc -N -w 15 $PS4_HOST $PS4_BINLOADER_PORT < $1"; return 0; fi
    if [ -n "${CTL_SEND_CMD:-}" ]; then $CTL_SEND_CMD "$1"; log "sent $(basename "$1") through CTL_SEND_CMD"; return 0; fi
    # No port check first: a bare connection to 9090 may use up BinLoader (2026-11-04: 9090 was open
    # at the watcher's one empty connection and closed 38 s later). The send's own connection decides.
    local reply="$WORK/$(basename "$1").reply" rc=0
    nc -N -w 15 "$PS4_HOST" "$PS4_BINLOADER_PORT" < "$1" > "$reply" 2>&1 || rc=$?
    # OpenBSD nc exits 1 and prints nothing when the connection is refused.
    if [ "$rc" != 0 ]; then
        log "BinLoader $PS4_HOST:$PS4_BINLOADER_PORT did not accept ($(head -c 200 "$reply" | tr -c '[:print:]' ' ')); FTP $(nc -z -w3 "$PS4_HOST" "$PS4_FTP_PORT" 2>/dev/null && echo up || echo down): enable BinLoader in GoldHEN"
        exit 4
    fi
    log "sent $(basename "$1") ($(stat -c %s "$1") bytes) to $PS4_HOST:$PS4_BINLOADER_PORT: nc rc=$rc, reply $(stat -c %s "$reply") bytes$( [ -s "$reply" ] && printf ': %s' "$(head -c 200 "$reply" | tr -c '[:print:]' '.')")"
}

# run_form FORM OP: send one command, wait for hello and done; sets NONCE and HELLO (0/1) and DONE (0/1)
run_form() {
    local form="$1" op="$2" file
    NONCE="$(new_nonce)"; HELLO=0; DONE=0
    file="$(payload "$form" "$NONCE" "$op")"
    log "ctl $CMD (op $op, form $form, nonce $NONCE, title_pid $TITLE_PID${PKG_REMOTE:+, pkg $PKG_REMOTE}${LAUNCH_ARGS[*]:+, args ${LAUNCH_ARGS[*]}})"
    if [ -n "$PATCH_ONLY" ]; then command cp -f "$file" "$PATCH_ONLY"; log "patched file: $PATCH_ONLY"; exit 0; fi
    if [ "$DRY" = 1 ]; then
        od -An -c -N 96 "$WORK/$NONCE.block" | sed 's/^/  block: /'
        send "$file"; return 0
    fi
    send "$file"
    if wait_for "$NONCE" " step=hello " "$HELLO_TIMEOUT"; then HELLO=1
    else log "no hello from the $form form in ${HELLO_TIMEOUT}s (netlog, klog and $PS4_DATA_ROOT/ctl/$NONCE.txt)"; return 0; fi
    wait_for "$NONCE" " done " "$TIMEOUT" && DONE=1 || true
    fetch_result "$NONCE"
}

# ------------------------------------------------------------------ main
if [ -n "$PKG_LOCAL" ] && [ "$DRY" = 0 ] && [ -z "$PATCH_ONLY" ]; then
    [ -n "${PS4_FTP_BASE:-}" ] || nc -z -w3 "$PS4_HOST" "$PS4_FTP_PORT" 2>/dev/null || { log "FTP $PS4_FTP_PORT closed on $PS4_HOST"; exit 4; }
    log "uploading $PKG_LOCAL -> $PKG_REMOTE"
    ftp_put "$PKG_LOCAL" "$PKG_REMOTE" || die "upload of $PKG_LOCAL failed or its size differs"
fi
if [ "$CMD" = probe ] && [ "$DRY" = 0 ] && [ -z "$PATCH_ONLY" ]; then
    [ -n "$LOGF" ] && [ -f "$LOGF" ] || die "probe needs --log FILE (a running logs.sh: the title's stamp line arrives there)"
    [ -n "$PKG_LOCAL" ] && [ -f "${PKG_LOCAL%.pkg}.stamp" ] || die "probe needs a local package with its .stamp beside it (pkg.sh writes it)"
fi

FORM_CACHE="$BUILD_DIR/ctl/form"
USED_FORM="$FORM"
if [ "$FORM" = auto ]; then
    USED_FORM="$(cat "$FORM_CACHE" 2>/dev/null || true)"
    if [ -z "$USED_FORM" ]; then
        if [ -n "$PATCH_ONLY" ] || [ "$DRY" = 1 ]; then USED_FORM=self
        else
            for f in self elf; do
                log "auto: trying the $f form with a status"
                run_form "$f" "${OPS[status]}"
                if [ "$HELLO" = 1 ]; then USED_FORM="$f"; printf '%s\n' "$f" > "$FORM_CACHE"; log "auto: the $f form runs (cached in $FORM_CACHE)"; break; fi
            done
            [ -n "$USED_FORM" ] || { log "auto: neither form said hello"; exit 3; }
            if [ "$CMD" = status ]; then OP=status_done; fi
        fi
    fi
fi
if [ "$OP" != status_done ]; then
    run_form "$USED_FORM" "$OP"
    [ "$DRY" = 1 ] && exit 0
    [ "$HELLO" = 1 ] || exit 3
fi

ALL="$(lines "$NONCE")"
printf '%s\n' "$ALL"
DONE_LINE="$(printf '%s\n' "$ALL" | grep -E ' done ' | tail -n1 || true)"
RC=0
if [ -z "$DONE_LINE" ]; then log "no done line from nonce $NONCE in ${TIMEOUT}s"; RC=3
elif [ "$(kv refused "$DONE_LINE")" != 0 ]; then RC=2
elif [ "$(kv failed "$DONE_LINE")" != 0 ]; then RC=5; fi

if [ "$CMD" = probe ]; then
    step() { printf '%s\n' "$ALL" | grep -E " step=$1 " | tail -n1 || true; }
    HL="$(step hello)"; LB="$(step libs)"; BA="$(printf '%s\n' "$ALL" | grep -E ' step=bigapp ' | head -n1 || true)"
    KL="$(step kill)"; IN="$(step install)"; LA="$(step launch)"; US="$(step user)"; PT="$(step pkg_title)"
    res() { local r; r="$(kv result "$1")"; printf '%s' "${r:-none}"; }
    WANT="$(cat "${PKG_LOCAL%.pkg}.stamp")"
    STAMP_MATCH=0; GOT_STAMP=-
    if [ "$(res "$LA")" = ok ]; then
        log "waiting up to ${CTL_STAMP_TIMEOUT:-120} s for the relaunched title's PW_MS pkg_stamp=$WANT"
        start=$SECONDS
        while [ $((SECONDS - start)) -lt "${CTL_STAMP_TIMEOUT:-120}" ]; do
            if grep -qF "PW_MS pkg_stamp=$WANT " "$LOGF"; then STAMP_MATCH=1; break; fi
            sleep 1
        done
        GOT_STAMP="$(grep -oE 'PW_MS pkg_stamp=[^ ]*' "$LOGF" | tail -n1 | sed 's/.*=//' || true)"
    fi
    LINE="PS4WINE x1 ctl hello=$([ -n "$HL" ] && echo ok || echo none) form=$USED_FORM nonce=$NONCE"
    LINE="$LINE pid=$(kv pid "$HL") title_pid=$(kv title_pid "$HL") same_pid=$(kv same_pid "$HL") app_id=$(kv app_id "$HL")"
    LINE="$LINE app_title=$(kv app_title "$HL") sandbox=$(kv sandbox "$HL") data=$(kv data "$HL")"
    LINE="$LINE libs=$(kv loaded "$LB") syms=$(kv syms "$LB") user=$(kv user "$US") bigapp=$(kv big_title "$BA")"
    LINE="$LINE big_proof_info=$(kv proof_info "$BA") big_proof_lnc=$(kv proof_lnc "$BA") pkg_title=$(kv title "$PT")"
    LINE="$LINE kill=$(res "$KL") kill_why=$(kv why "$KL") lnc_kill=$(kv lnc_kill "$KL") sys_kill=$(kv sys_kill "$KL")"
    LINE="$LINE install=$(res "$IN") install_seq=$(kv seq "$IN") install_direct=$(kv direct "$IN")"
    LINE="$LINE install_prepare=$(kv prepare "$IN") install_overwrite=$(kv overwrite "$IN") install_ms=$(kv ms "$IN")"
    LINE="$LINE launch=$(res "$LA") launch_via=$(kv via "$LA") lnc_launch=$(kv lnc_launch "$LA") sys_launch=$(kv sys_launch "$LA")"
    LINE="$LINE stamp_match=$STAMP_MATCH stamp=$GOT_STAMP want_stamp=$WANT dialog=unjudged"
    LINE="$LINE done=$([ -n "$DONE_LINE" ] && echo 1 || echo 0) ctl_build=$(kv build "$HL")"
    LINE="$(printf '%s' "$LINE" | sed -E 's/=( |$)/=-\1/g')"
    printf '%s H %s\n' "$(date +%H:%M:%S)" "$LINE" >> "$LOGF"
    printf '%s\n' "$LINE"
    log "x1: take a shot now (close the viewer first), judge it, then: ctl.sh judge --log $LOGF --dialog 0|1 --shot FILE"
fi
exit "$RC"

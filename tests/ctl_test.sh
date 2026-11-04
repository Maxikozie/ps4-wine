#!/usr/bin/env bash
# ctl_test.sh: host tests of the ctl (docs/ps4/HANDOFF-loop.md, phase 1): ctl/ctl.c's steps and safety
# against a fake console (tests/ctl_fake_console.c), and scripts/ps4/ctl.sh's block, patching,
# refusals, result parsing, exit codes, --dry-run, the auto form and probe's x1 line, end to end
# through a fake BinLoader that runs ctl.c on the patched payload.
set -euo pipefail

usage() {
    cat <<USAGE
usage: tests/ctl_test.sh

Builds ctl/ctl.c for the host with tests/ctl_fake_console.c (UBSan on) and tests/ctl_block_dump.c
under build/test/, then runs every case. Exit 0 when every case matches.
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-/usr/lib/llvm-18/bin/clang}"
T="$ROOT/build/test/ctl"
rm -rf "$T"; mkdir -p "$T/ftp/data/pkg" "$T/ftp/data/ps4-wine/ctl" "$T/build"
fails=0
ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s: %s\n' "$1" "$2"; fails=$((fails + 1)); }

"$CC" -std=gnu11 -O1 -g -Wall -Wextra -Werror -fsanitize=undefined -fno-sanitize-recover=all -I"$ROOT/ctl" \
    "$ROOT/ctl/ctl.c" "$ROOT/tests/ctl_fake_console.c" -o "$T/ctl_host"
"$CC" -std=gnu11 -O1 -Wall -Wextra -Werror -I"$ROOT/ctl" "$ROOT/tests/ctl_block_dump.c" -o "$T/ctl_block_dump"
HARNESS="$T/ctl_host"; DUMP="$T/ctl_block_dump"

# ------------------------------------------------------------------ ctl.c against the fake console
# hcase NAME WANT_SUBSTRING [ENV...]: run the harness with ENV and look for WANT in its output
hcase() {
    local name="$1" want="$2" out; shift 2
    out="$(env "$@" "$HARNESS" 2>&1)" || { bad "$name" "harness exit $? : $(printf '%s' "$out" | tail -n2)"; return; }
    if [[ "$out" == *"runtime error"* ]]; then bad "$name" "UBSan: $(printf '%s' "$out" | grep -m1 'runtime error')"
    elif [[ "$out" != *"$want"* ]]; then bad "$name" "no '$want' in: $(printf '%s' "$out" | grep -E 'step=(kill|install|launch) |done ' | tr '\n' '|')"
    else ok "$name"; fi
}
hcase status-running       "proof_info=1 proof_lnc=1 contra_info=0 contra_lnc=0" CTLT_OP=status CTLT_RUNNING=1
hcase status-done          "done ok=0 refused=0 failed=0 op=status"              CTLT_OP=status CTLT_RUNNING=1
hcase lnc-from-sysservice  "loaded=5/6 syms=20/20"                               CTLT_OP=status
hcase kill-ok              "step=kill rc=0x00000000"                              CTLT_OP=kill CTLT_RUNNING=1
hcase kill-ok-result       "result=ok target=0x60000010"                          CTLT_OP=kill CTLT_RUNNING=1
hcase kill-not-running     "result=not_running"                                   CTLT_OP=kill
hcase kill-same-pid        "result=refused why=same_pid"                          CTLT_OP=kill CTLT_RUNNING=1 CTLT_PID=777 CTLT_TITLE_PID=777
hcase kill-same-app        "result=refused why=same_app"                          CTLT_OP=kill CTLT_RUNNING=1 CTLT_SELF_APP=1
hcase kill-background      "result=refused why=no_proof"                          CTLT_OP=kill CTLT_RUNNING=1 CTLT_BACKGROUND=1
hcase kill-refused-done    "done ok=0 refused=1 failed=0"                         CTLT_OP=kill CTLT_RUNNING=1 CTLT_PID=777 CTLT_TITLE_PID=777
hcase kill-sys-fallback    "result=ok target=0x60000010 lnc_kill=0x80aa0003 sys_kill=0x00000000" CTLT_OP=kill CTLT_RUNNING=1 CTLT_KILL_FAILS=1
hcase kill-fails           "result=fail target=0x60000010 lnc_kill=0x80aa0003 sys_kill=0x80aa0003" CTLT_OP=kill CTLT_RUNNING=1 CTLT_KILL_FAILS=2
hcase kill-dry             "result=dry"                                           CTLT_OP=kill CTLT_RUNNING=1 CTLT_DRY=1
hcase install-pkg-title    "result=refused why=pkg_title"                         CTLT_OP=install CTLT_PKG_TITLE=CUSA12345
hcase install-running      "result=refused why=title_running"                     CTLT_OP=install CTLT_RUNNING=1
hcase install-direct       "result=ok seq=direct"                                 CTLT_OP=install
hcase install-overwrite    "result=ok seq=overwrite direct=0x80990015 prepare=0x00000000 overwrite=0x00000000" CTLT_OP=install CTLT_DIRECT_FAILS=1
hcase install-no-lib       "result=refused why=pkg_title"                         CTLT_OP=install CTLT_NO_LIB=libSceAppInstUtil
hcase install-no-lib-libs  "loaded=4/6 syms=14/20"                                CTLT_OP=install CTLT_NO_LIB=libSceAppInstUtil
hcase install-dry          "step=install rc=0x00000000 ms=0 result=dry"           CTLT_OP=install CTLT_DRY=1
hcase launch-lnc           "result=ok via=lnc"                                    CTLT_OP=launch
hcase launch-param         "FAKE lnc_launch title=PSWN00001 arg0=--ctl-x1 size=32 user=4096 flag=2" CTLT_OP=launch
hcase launch-sys-fallback  "result=ok via=sys lnc_launch=0x80940018"              CTLT_OP=launch CTLT_LNC_LAUNCH_FAILS=1
hcase cycle                "done ok=3 refused=0 failed=0 op=cycle"                CTLT_OP=cycle CTLT_RUNNING=1
hcase cycle-not-running    "done ok=2 refused=0 failed=0 op=cycle"                CTLT_OP=cycle
hcase cycle-stops-on-refusal "step=cycle_stop ok=0 refused=1"                     CTLT_OP=cycle CTLT_RUNNING=1 CTLT_SELF_APP=1
hcase probe-klog-done      "KLOG PS4CTL host-test done ok=3"                      CTLT_OP=probe CTLT_RUNNING=1
hcase none-hello-only      "done ok=0 refused=0 failed=0 op=none"                 CTLT_OP=none
hcase bad-nonce            "done ok=0 refused=1 failed=0 op=kill why=bad_block"   CTLT_OP=kill CTLT_NONCE=bad/nonce

# ------------------------------------------------------------------ ctl.sh
CTL="$ROOT/scripts/ps4/ctl.sh"
export BUILD_DIR="$T/build" PS4_FTP_BASE="file://$T/ftp" PS4_HOST=127.0.0.1
cat > "$T/fake-create-fself" <<'EOF'
#!/usr/bin/env bash
# create-fself's arguments; the "fSELF" is the ELF copied (the block test only needs the bytes).
in=""; out=""
while [ $# -gt 0 ]; do case "$1" in -in=*) in="${1#-in=}" ;; --eboot) out="$2"; shift ;; esac; shift; done
cp "$in" "$out"
EOF
cat > "$T/fake-send" <<EOF
#!/usr/bin/env bash
# BinLoader on the host: runs ctl.c (the harness) on the patched payload, writes its result file into
# the fake FTP root and, with CTL_FAKE_LOG, its lines into a logs.sh-style capture.
set -euo pipefail
f="\$1"
case "\${CTL_FAKE_MODE:-run}" in
    silent) exit 0 ;;
    silent-self) [[ "\$f" == *.bin ]] && exit 0 ;;
esac
out="\$(CTLT_BLOCK_FILE="\$f" "$HARNESS" | grep -a '^PS4CTL ' || true)"
nonce="\$(printf '%s\n' "\$out" | head -n1 | awk '{ print \$2 }')"
printf '%s\n' "\$out" > "$T/ftp/data/ps4-wine/ctl/\$nonce.txt"
printf '%s\n' "\$f" >> "$T/sent.txt"
if [ -n "\${CTL_FAKE_LOG:-}" ]; then
    printf '%s\n' "\$out" | sed "s/^/\$(date +%H:%M:%S) N /" >> "\$CTL_FAKE_LOG"
    if [ -n "\${CTL_FAKE_STAMP:-}" ] && grep -q 'step=launch .*result=ok' <<<"\$out"; then
        printf '%s N PW_MS pkg_stamp=%s argv=--ctl-x1 pid=4321\n' "\$(date +%H:%M:%S)" "\$CTL_FAKE_STAMP" >> "\$CTL_FAKE_LOG"
    fi
fi
EOF
chmod +x "$T/fake-create-fself" "$T/fake-send"
export CTL_CREATE_FSELF="$T/fake-create-fself" CTL_SEND_CMD="$T/fake-send"
TPL="$HARNESS"   # one magic, from ctl_cmd's initializer; serves as both forms' template

# layout: ctl.sh's numbers are the header's
if [ "$("$CTL" --print-layout)" = "$("$DUMP" layout)" ]; then ok layout; else bad layout "$("$CTL" --print-layout) != $("$DUMP" layout)"; fi
# the template holds exactly one magic
n="$(LC_ALL=C grep -c -obUaF PS4WINE-CTL-CMD1 "$TPL" || true)"
[ "$n" = 1 ] && ok template-one-magic || bad template-one-magic "$n copies"

# scase NAME WANT_RC WANT_SUBSTRING CTL_ARGS...: run ctl.sh, compare its exit code and output
scase() {
    local name="$1" want_rc="$2" want="$3" out rc=0; shift 3
    out="$("$CTL" --elf "$TPL" --plain "$TPL" "$@" 2>&1)" || rc=$?
    if [ "$rc" != "$want_rc" ]; then bad "$name" "exit $rc (want $want_rc): $(printf '%s' "$out" | tail -n3 | tr '\n' '|')"
    elif [[ -n "$want" && "$out" != *"$want"* ]]; then bad "$name" "no '$want' in: $(printf '%s' "$out" | tail -n3 | tr '\n' '|')"
    else ok "$name"; fi
}

# patching
"$CTL" --elf "$TPL" --plain "$TPL" --form elf --title-pid 70000 --patch-only "$T/p.elf" launch --ctl-x1 a2 2>/dev/null
d="$("$DUMP" "$T/p.elf")"
[[ "$d" =~ ^version=1\ op=4\ title_pid=70000\ flags=0\ nonce=[0-9]{14}-[0-9a-f]{8}\ pkg=-\ argc=2\ arg0=--ctl-x1\ arg1=a2$ ]] &&
    ok patch-launch || bad patch-launch "$d"
"$CTL" --elf "$TPL" --plain "$TPL" --form self --console-dry --patch-only "$T/p.bin" install /data/pkg/ps4-wine-1+dirty.pkg 2>/dev/null
d="$("$DUMP" "$T/p.bin")"
[[ "$d" == *"op=3 title_pid=0 flags=1 "*"pkg=/data/pkg/ps4-wine-1+dirty.pkg argc=0" ]] && ok patch-install-self || bad patch-install-self "$d"
cmp -s <(head -c 1000 "$TPL") <(head -c 1000 "$T/p.elf") && ok patch-keeps-rest || bad patch-keeps-rest "bytes before the block changed"
[ "$(stat -c %s "$TPL")" = "$(stat -c %s "$T/p.elf")" ] && ok patch-same-size || bad patch-same-size "size changed"

# refusals
head -c 8192 /dev/urandom | tr -d 'P' > "$T/nomagic.elf"
scase refuse-no-magic 2 "holds 0 copies" --elf "$T/nomagic.elf" --plain "$T/nomagic.elf" --form elf --patch-only "$T/x" status
cat "$TPL" "$TPL" > "$T/twomagic.elf"
scase refuse-two-magics 2 "holds 2 copies" --elf "$T/twomagic.elf" --plain "$T/twomagic.elf" --form elf --patch-only "$T/x" status
scase refuse-long-arg 1 "at most 63" --form elf --patch-only "$T/x" launch "$(printf 'a%.0s' {1..64})"
scase refuse-nine-args 1 "at most 8" --form elf --patch-only "$T/x" launch 1 2 3 4 5 6 7 8 9
scase refuse-pkg-space 1 "characters the ctl does not take" --form elf --patch-only "$T/x" install "/data/pkg/a b.pkg"
scase refuse-pkg-path 1 "local .pkg or a console path" --form elf --patch-only "$T/x" install /system/x.bin
scase refuse-kill-args 1 "kill takes no arguments" --form elf kill now
scase refuse-form 1 "--form must be" --form exe status
scase refuse-command 1 "usage:" frobnicate
out="$("$ROOT/scripts/ps4/deploy.sh" x.pkg --install 2>&1)" && rc=0 || rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"ctl.sh install"* ]] && ok deploy-install-exit2 || bad deploy-install-exit2 "exit $rc: $out"

# --dry-run
scase dry-run 0 "nc -N -w 15 127.0.0.1 9090" --form elf --dry-run kill

# end to end through the fake BinLoader (no --log: the result file over the fake FTP)
scase e2e-status 0 "done ok=0 refused=0 failed=0 op=status" --form elf status
CTLT_RUNNING=1 scase e2e-status-running 0 "proof_info=1 proof_lnc=1" --form elf status
CTLT_RUNNING=1 scase e2e-kill 0 "result=ok" --form elf kill
CTLT_RUNNING=1 CTLT_PID=777 scase e2e-kill-same-pid 2 "why=same_pid" --form elf --title-pid 777 kill
CTLT_RUNNING=1 CTLT_KILL_FAILS=2 scase e2e-kill-fails 5 "result=fail" --form elf kill
CTLT_PKG_TITLE=CUSA12345 scase e2e-install-foreign 2 "why=pkg_title" --form elf install /data/pkg/x.pkg
head -c 70000 /dev/urandom > "$T/ps4-wine-test.pkg"
scase e2e-install-upload 0 "result=ok seq=direct" --form elf install "$T/ps4-wine-test.pkg"
cmp -s "$T/ps4-wine-test.pkg" "$T/ftp/data/pkg/ps4-wine-test.pkg" && ok e2e-uploaded || bad e2e-uploaded "the package did not arrive whole"
CTL_FAKE_MODE=silent scase e2e-silent 3 "no hello" --form elf --hello-timeout 2 status
PS4_BINLOADER_PORT=1 CTL_SEND_CMD="" scase e2e-unreachable 4 "enable BinLoader" --form elf status
# auto: the self form says nothing, the plain form answers and is cached
rm -f "$BUILD_DIR/ctl/form" "$T/sent.txt"
CTL_FAKE_MODE=silent-self scase e2e-auto 0 "the elf form runs" --hello-timeout 2 status
[ "$(cat "$BUILD_DIR/ctl/form" 2>/dev/null)" = elf ] && ok e2e-auto-cached || bad e2e-auto-cached "form cache: $(cat "$BUILD_DIR/ctl/form" 2>/dev/null)"
: > "$T/sent.txt"
CTLT_RUNNING=1 scase e2e-auto-uses-cache 0 "result=ok" kill
[ "$(wc -l < "$T/sent.txt")" = 1 ] && [[ "$(cat "$T/sent.txt")" == *.elf ]] && ok e2e-auto-one-send || bad e2e-auto-one-send "$(cat "$T/sent.txt")"

# probe (x1) with a log: the x1 line, check.sh x1 before and after judge
printf '20261104T050000Z-abc1234\n' > "$T/ps4-wine-test.stamp"
LOGF="$T/x1.log"; : > "$LOGF"
CTLT_RUNNING=1 CTL_FAKE_LOG="$LOGF" CTL_FAKE_STAMP=20261104T050000Z-abc1234 CTL_STAMP_TIMEOUT=5 \
    scase e2e-probe 0 "stamp_match=1" --form elf --log "$LOGF" probe "$T/ps4-wine-test.pkg"
line="$(grep 'PS4WINE x1 ctl' "$LOGF" | tail -n1)"
for kv in hello=ok form=elf kill=ok install=ok install_seq=direct launch=ok launch_via=lnc stamp_match=1 dialog=unjudged bigapp=PSWN00001 libs=5/6; do
    [[ " $line " == *" $kv "* ]] || bad e2e-probe-line "no $kv in: $line"
done
ok e2e-probe-fields
out="$("$ROOT/scripts/ps4/check.sh" x1 --log "$LOGF" 2>&1)" && rc=0 || rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"| FAIL | dialog=unjudged != 0"* ]] && ok e2e-check-unjudged || bad e2e-check-unjudged "exit $rc: $out"
printf 'png' > "$T/x1-shot.png"
"$CTL" judge --log "$LOGF" --dialog 0 --shot "$T/x1-shot.png" >/dev/null 2>&1
out="$("$ROOT/scripts/ps4/check.sh" x1 --log "$LOGF" 2>&1)" && rc=0 || rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"| x1 | build "*"| PASS | PS4WINE x1 ctl "*" dialog=0 "*" dialog_by=eye shot=x1-shot.png |"* ]] && ok e2e-check-judged || bad e2e-check-judged "exit $rc: $out"
# a stamp that does not match the package's
LOGF="$T/x1b.log"; : > "$LOGF"
CTLT_RUNNING=1 CTL_FAKE_LOG="$LOGF" CTL_FAKE_STAMP=20250101T000000Z-old CTL_STAMP_TIMEOUT=2 \
    scase e2e-probe-old-stamp 0 "stamp_match=0 stamp=20250101T000000Z-old" --form elf --log "$LOGF" probe "$T/ps4-wine-test.pkg"
scase probe-needs-log 1 "probe needs --log" --form elf probe "$T/ps4-wine-test.pkg"

if [ "$fails" -ne 0 ]; then echo "ctl_test: $fails failure(s)"; exit 1; fi
echo "ctl_test: all passed"

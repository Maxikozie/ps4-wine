#!/usr/bin/env bash
# loop-spike.sh: phase 0 of the loop harness (docs/ps4/HANDOFF-loop.md). Measures what Claude Code does
# headless (-p, plan mode, resume, budgets, hooks, --bg, signals) with cheap prompts, in a scratch
# project (build/loop-spike/proj) so this repo's session list, settings and files stay untouched. Raw
# output of every call goes to logs/loop/spike/<ts>/ (NAME.cmd, NAME.out, NAME.err, NAME.rc) plus
# summary.tsv; the reading of it is written by hand into HANDOFF-loop.md. Re-run after a CLI upgrade.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/loop-spike.sh [--only S1,S3,...] [--budget USD] [--out DIR] [--dry-run]

  --only LIST   run only these items (S1-S6, S2d, S4d, S8-S15, S13c, S17; S7 and S16 are not provokable)
  --budget USD  stop starting calls once the summed total_cost_usd reaches this (default 3)
  --out DIR     raw output directory (default logs/loop/spike/<timestamp>)
  --dry-run     print every claude command, run nothing, create nothing
Cheap model: SPIKE_MODEL_CHEAP (default haiku); production model: SPIKE_MODEL_PROD (default opus).
Every child claude runs with CLAUDE*/AI_AGENT/NTFY_* removed from its environment.
USAGE
}

ONLY=""; BUDGET=3; OUT=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

CHEAP="${SPIKE_MODEL_CHEAP:-haiku}"
PROD="${SPIKE_MODEL_PROD:-opus}"
SPIKE="$BUILD_DIR/loop-spike"
PROJ="$SPIKE/proj"
OUT="${OUT:-$LOGS_DIR/loop/spike/$(timestamp)}"
[ "$DRY" = 1 ] || need_cmd claude

# The child's environment: no parent-session variables (CLAUDECODE, CLAUDE_CODE_*, ...), no NTFY_*.
UNSET=()
while IFS='=' read -r name _; do
    case "$name" in CLAUDE*|AI_AGENT|NTFY_*) UNSET+=(-u "$name") ;; esac
done < <(env)

want() { [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]; }
uuid() { uuidgen | tr 'A-Z' 'a-z'; }

cost_of() {  # total_cost_usd of a json or stream-json output file, 0 when absent
    python3 -I - "$1" <<'PY'
import json, sys
cost = 0.0
try:
    text = open(sys.argv[1]).read()
except OSError:
    text = ""
docs = []
try:
    docs = [json.loads(text)]
except ValueError:
    for line in text.splitlines():
        try:
            docs.append(json.loads(line))
        except ValueError:
            pass
for d in docs:
    if isinstance(d, dict) and isinstance(d.get("total_cost_usd"), (int, float)):
        cost = d["total_cost_usd"]
print(f"{cost:.6f}")
PY
}

spent() { [ -f "$OUT/cost.txt" ] && cat "$OUT/cost.txt" || echo 0; }
over_budget() { python3 -I -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$(spent)" "$BUDGET"; }
add_cost() { python3 -I -c "import sys; print(f'{float(sys.argv[1]) + float(sys.argv[2]):.6f}')" "$(spent)" "$1" > "$OUT/cost.txt.new"; mv "$OUT/cost.txt.new" "$OUT/cost.txt"; }

# run NAME [ENV=V ...] -- claude args...: foreground, 600 s cap, in the scratch project.
run() {
    local name="$1"; shift
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    if [ "$DRY" = 1 ]; then
        printf '%s: (cd %s && env %s %s claude %s)\n' "$name" "$PROJ" "${UNSET[*]}" "${envs[*]:-}" "$*"
        return 0
    fi
    if over_budget; then
        log "$name: skipped, \$$(spent) spent of \$$BUDGET"; echo skipped > "$OUT/$name.rc"; return 0
    fi
    printf '%q ' env "${envs[@]}" claude "$@" > "$OUT/$name.cmd"; echo >> "$OUT/$name.cmd"
    local rc=0
    ( builtin cd "$PROJ" && timeout 600 env "${UNSET[@]}" "${envs[@]}" claude "$@" ) \
        > "$OUT/$name.out" 2> "$OUT/$name.err" < /dev/null || rc=$?
    echo "$rc" > "$OUT/$name.rc"
    add_cost "$(cost_of "$OUT/$name.out")"
    log "$name: rc=$rc spent=\$$(spent)"
}

hook_mark() { [ "$DRY" = 1 ] || : > "$PROJ/.claude/hook-calls.log"; }
hook_take() { [ "$DRY" = 1 ] || command cp -f "$PROJ/.claude/hook-calls.log" "$OUT/$1.hooks.log"; }
files_take() { [ "$DRY" = 1 ] || ( builtin cd "$PROJ" && find . -path ./.git -prune -o -type f -newer "$OUT/.start-$1" -print ) > "$OUT/$1.files" 2>/dev/null || true; }
start_mark() { [ "$DRY" = 1 ] || touch "$OUT/.start-$1"; }

setup_project() {
    [ "$DRY" = 1 ] && { log "would create $PROJ"; return 0; }
    rm -rf "$SPIKE"
    mkdir -p "$PROJ/.claude" "$OUT"
    git -C "$PROJ" init -q
    printf 'hello\nsecond line\n' > "$PROJ/hello.txt"
    printf '#!/usr/bin/env bash\necho hi from run-me\n' > "$PROJ/run-me.sh"
    git -C "$PROJ" add -A
    git -C "$PROJ" -c user.name=spike -c user.email=spike@localhost commit -qm init
    # Logs every PreToolUse call with the env it sees, before any fast path, so a hook that never
    # fires and a hook that fires without our variables can be told apart. Denies deny-me (JSON) and
    # deny2-me (exit 2).
    cat > "$PROJ/.claude/spike-hook.sh" <<'HOOK'
#!/usr/bin/env bash
in="$(cat)"
log="$(dirname "$0")/hook-calls.log"
printf '%s\tsession=%s\trole=%s\t%s\n' "$(date +%s.%N)" "${PS4_LOOP_SESSION:-unset}" "${PS4_LOOP_ROLE:-unset}" \
    "$(printf '%s' "$in" | tr '\n' ' ')" >> "$log"
case "$in" in
    *deny2-me*) echo "spike deny by exit 2" >&2; exit 2 ;;
    *deny-me*) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"spike deny by JSON"}}\n' ;;
esac
exit 0
HOOK
    chmod +x "$PROJ/.claude/spike-hook.sh"
    cat > "$PROJ/.claude/settings.json" <<'JSON'
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/spike-hook.sh"}]}]}}
JSON
    # A second hook, given only through --settings (S11b), logging to its own file.
    cat > "$SPIKE/flag-hook.sh" <<'HOOK'
#!/usr/bin/env bash
in="$(cat)"
printf '%s\tsession=%s\t%s\n' "$(date +%s.%N)" "${PS4_LOOP_SESSION:-unset}" "$(printf '%s' "$in" | tr '\n' ' ')" \
    >> "$(dirname "$0")/flag-hook.log"
exit 0
HOOK
    chmod +x "$SPIKE/flag-hook.sh"
    printf '{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "%s"}]}]}}\n' \
        "$SPIKE/flag-hook.sh" > "$SPIKE/flag-settings.json"
    claude --version > "$OUT/version.txt"
    echo 0 > "$OUT/cost.txt"
}

COMMON_CHEAP=(--model "$CHEAP" --effort low --strict-mcp-config)
COMMON_PROD=(--model "$PROD" --effort low --strict-mcp-config)
PLAN_SCHEMA='{"type":"object","properties":{"plan":{"type":"string"},"steps":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"}},"required":["id","title"]}}},"required":["plan","steps"]}'

setup_project
log "out: $OUT"
U1="$(uuid)"

if want S1; then
    run S1 -- -p "Reply with exactly: ok" --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.10 \
        --session-id "$U1" -n spike-s1
fi

if want S2; then
    run S2a -- -p "What is 2+2? Put the number in the answer field." --output-format json "${COMMON_CHEAP[@]}" \
        --max-budget-usd 0.10 --json-schema '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}'
    run S2b -- -p "Give any number n." --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.10 \
        --json-schema '{"type":"object","properties":{"n":{"type":"integer","minimum":5,"maximum":3}},"required":["n"]}'
    run S2c -- -p "Repeat your previous reply in the reply field." --output-format json "${COMMON_CHEAP[@]}" \
        --max-budget-usd 0.10 --resume "$U1" \
        --json-schema '{"type":"object","properties":{"reply":{"type":"string"}},"required":["reply"]}'
fi

if want S2d; then  # a restricted --tools list together with --json-schema (StructuredOutput is a tool call)
    run S2d -- -p "What is 2+2? Put the number in the answer field." --output-format json "${COMMON_CHEAP[@]}" \
        --max-budget-usd 0.10 --tools "Read,Grep,Glob" \
        --json-schema '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}'
fi

if want S4d; then  # --tools on --resume: plan mode with Read only, then resumed with the default tools and acceptEdits
    U4d="$(uuid)"
    run S4d1 -- -p "Reply with the word one." --output-format stream-json --verbose --permission-mode plan \
        --tools "Read" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10 --session-id "$U4d"
    start_mark S4d2
    run S4d2 -- -p "Create the file tools-resume.txt containing the word two with your Write tool, then reply done." \
        --output-format stream-json --verbose --resume "$U4d" --permission-mode acceptEdits --tools default \
        "${COMMON_CHEAP[@]}" --max-budget-usd 0.10
    files_take S4d2
fi

if want S3; then
    PLANS="$HOME/.claude/plans"
    for v in a b c; do
        start_mark "S3$v"; hook_mark
        case "$v" in
            a) extra=(--permission-prompts none) ;;
            b) extra=(--permission-prompts host) ;;
            c) extra=(--permission-prompts none --json-schema "$PLAN_SCHEMA") ;;
        esac
        run "S3$v" PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=plan -- -p \
            "Plan how to append the line 'bye' to hello.txt in this project. Keep the plan to five lines and two steps. When the plan is ready, finish the way plan mode asks you to." \
            --output-format json --permission-mode plan "${COMMON_PROD[@]}" --max-budget-usd 0.50 "${extra[@]}" -n "spike-s3$v"
        hook_take "S3$v"; files_take "S3$v"
        [ "$DRY" = 1 ] || find "$PLANS" -maxdepth 1 -type f -newer "$OUT/.start-S3$v" > "$OUT/S3$v.planfiles" 2>/dev/null || true
    done
fi

if want S4; then
    U4="$(uuid)"
    run S4a -- -p "Reply with the word one" --output-format stream-json --verbose --permission-mode plan \
        "${COMMON_CHEAP[@]}" --max-budget-usd 0.10 --session-id "$U4" -n spike-s4
    start_mark S4b; hook_mark
    run S4b -- -p "Create the file resume-write.txt containing the word two, then reply done." \
        --output-format stream-json --verbose --resume "$U4" --permission-mode acceptEdits --effort high \
        --model sonnet --strict-mcp-config --max-budget-usd 0.30
    hook_take S4b; files_take S4b
fi

if want S11; then
    start_mark S11a; hook_mark
    run S11a PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=exec -- -p \
        "Do these four steps in order and report the result of each: 1) Read hello.txt. 2) Write the word x to the file deny-me.txt. 3) Write the word y to the file deny2-me.txt. 4) Write the word z to the file allow-me.txt." \
        --output-format json --permission-mode acceptEdits "${COMMON_CHEAP[@]}" --max-budget-usd 0.15
    hook_take S11a; files_take S11a
    [ "$DRY" = 1 ] || : > "$SPIKE/flag-hook.log"
    run S11b PS4_LOOP_SESSION=1 -- -p "Read hello.txt and reply with its first line." --output-format json \
        --setting-sources user --settings "$SPIKE/flag-settings.json" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10
    [ "$DRY" = 1 ] || command cp -f "$SPIKE/flag-hook.log" "$OUT/S11b.flaghooks.log" 2>/dev/null || true
    if [ "$DRY" = 0 ]; then  # S11c: the fast path's cost, 100 calls with the session flag unset
        printf '#!/usr/bin/env bash\n[ "${PS4_LOOP_SESSION:-}" = 1 ] || exit 0\nexec python3 -c "pass"\n' > "$SPIKE/fast.sh"
        chmod +x "$SPIKE/fast.sh"
        s=$(date +%s%N)
        for _ in $(seq 100); do echo '{}' | env -u PS4_LOOP_SESSION "$SPIKE/fast.sh"; done
        e=$(date +%s%N)
        s2=$(date +%s%N)
        for _ in $(seq 100); do echo '{}' | PS4_LOOP_SESSION=1 "$SPIKE/fast.sh"; done
        e2=$(date +%s%N)
        printf 'fast_path_us_per_call=%d python_path_us_per_call=%d\n' $(( (e - s) / 100000 )) $(( (e2 - s2) / 100000 )) \
            > "$OUT/S11c.txt"
        log "S11c: $(cat "$OUT/S11c.txt")"
    fi
fi

if want S12; then
    start_mark S12; hook_mark
    run S12 PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=exec -- -p \
        "Do these four steps in order and report the result of each, continuing after any refusal: 1) Run: bash run-me.sh 2) Write the word z to the file auto-write.txt 3) Run: git push origin main 4) Run: rm -rf /tmp/spike-nonexistent-dir-4711" \
        --output-format json --permission-mode auto --permission-prompts none "${COMMON_PROD[@]}" --max-budget-usd 0.50
    hook_take S12; files_take S12
fi

if want S13; then
    start_mark S13a; hook_mark
    run S13a PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=review -- -p \
        "Use the Agent tool exactly once with subagent_type general-purpose. Ask the subagent to create the file sub-write-a.txt containing the word x, using its Write tool or Bash, and to list the tools it has. Then report exactly what the subagent said." \
        --output-format json --tools "Read,Grep,Glob,Agent" "${COMMON_PROD[@]}" --max-budget-usd 0.50
    hook_take S13a; files_take S13a
    start_mark S13b; hook_mark
    run S13b PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=plan -- -p \
        "Use the Agent tool exactly once with subagent_type general-purpose. Ask the subagent to create the file sub-write-b.txt containing the word x, using its Write tool or Bash, and to list the tools it has. Then report exactly what the subagent said." \
        --output-format json --permission-mode plan --permission-prompts none "${COMMON_PROD[@]}" --max-budget-usd 0.50
    hook_take S13b; files_take S13b
fi

if want S13c; then
    start_mark S13c; hook_mark
    run S13c PS4_LOOP_SESSION=1 PS4_LOOP_ROLE=plan -- -p \
        "This is a read-only check of tool availability. Use the Agent tool exactly once with subagent_type general-purpose and ask it to use no tools at all and only reply with the exact names of every tool it has. Then report that list verbatim." \
        --output-format json --permission-mode plan --permission-prompts none "${COMMON_PROD[@]}" --max-budget-usd 0.50
    hook_take S13c
fi

if want S8; then
    for sig in INT TERM; do
        name="S8$sig"; U8="$(uuid)"
        if [ "$DRY" = 1 ]; then
            printf '%s: background claude -p (sleep 30 via Bash) --session-id U, then kill -%s, then --resume\n' "$name" "$sig"
            continue
        fi
        over_budget && { log "$name: skipped (budget)"; continue; }
        ( builtin cd "$PROJ" && exec env "${UNSET[@]}" claude -p \
            "Run this exact bash command: python3 -c 'import time; time.sleep(30)' ; then reply with the word done." \
            --output-format stream-json --verbose --permission-mode dontAsk --allowedTools "Bash(python3 *)" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10 \
            --session-id "$U8" ) > "$OUT/$name.out" 2> "$OUT/$name.err" < /dev/null &
        pid=$!
        for _ in $(seq 240); do grep -q '"tool_use"' "$OUT/$name.out" 2>/dev/null && break; sleep 0.5; done
        sleep 5
        grep -q '"tool_result"' "$OUT/$name.out" && echo "tool had already returned" > "$OUT/$name.note"
        kill "-$sig" "$pid" 2>/dev/null || true
        rc=0; wait "$pid" || rc=$?
        echo "$rc" > "$OUT/$name.rc"
        add_cost "$(cost_of "$OUT/$name.out")"
        log "$name: killed with $sig, rc=$rc"
        run "${name}r" -- -p "What happened to the python sleep command you ran? Answer in one sentence." \
            --output-format json --resume "$U8" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10
    done
fi

if want S9; then
    if [ "$DRY" = 1 ]; then
        printf 'S9: claude --bg -n spike-bg ...; claude --bg -p ...; claude agents --json --all; claude logs ID\n'
    elif ! over_budget; then
        rc=0
        ( builtin cd "$PROJ" && env "${UNSET[@]}" timeout 120 claude --bg -n spike-bg "${COMMON_CHEAP[@]}" \
            "Reply with exactly: ok" ) > "$OUT/S9a.out" 2> "$OUT/S9a.err" < /dev/null || rc=$?
        echo "$rc" > "$OUT/S9a.rc"
        rc=0
        ( builtin cd "$PROJ" && env "${UNSET[@]}" timeout 120 claude --bg -p -n spike-bg-p "${COMMON_CHEAP[@]}" \
            --output-format json "Reply with exactly: ok" ) > "$OUT/S9b.out" 2> "$OUT/S9b.err" < /dev/null || rc=$?
        echo "$rc" > "$OUT/S9b.rc"
        sleep 45
        env "${UNSET[@]}" claude agents --json --all > "$OUT/S9c.agents.json" 2> "$OUT/S9c.err" || true
        for id in $(grep -oE '\b[0-9a-z]{6,12}\b' "$OUT/S9a.out" "$OUT/S9b.out" 2>/dev/null | cut -d: -f2 | sort -u | head -4); do
            env "${UNSET[@]}" timeout 30 claude logs "$id" > "$OUT/S9d.logs-$id.txt" 2>&1 || true
        done
        log "S9: --bg rc=$(cat "$OUT/S9a.rc") --bg -p rc=$(cat "$OUT/S9b.rc")"
    fi
fi

if want S5; then
    U5="$(uuid)"
    run S5a -- -p "Read hello.txt, then read run-me.sh, then write a 300-word story about both." --output-format json \
        "${COMMON_CHEAP[@]}" --max-budget-usd 0.005 --session-id "$U5"
    run S5b -- -p "Reply with the word resumed." --output-format json --resume "$U5" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10
fi

if want S6; then
    run S6a -- -p "Reply ok" --output-format json --model no-such-model-xyz --strict-mcp-config --max-budget-usd 0.05
    run S6b -- -p "Reply ok" --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05 --json-schema '{bad'
    run S6c -- -p "Reply ok" --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05 \
        --resume 00000000-0000-4000-8000-000000000000
    run S6d -- -p "Reply ok" --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05 --session-id "$U1"
fi

if want S10; then
    run S10 -- -p "Reply ok" --output-format stream-json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05
fi

if want S14; then
    run S14a -- -p "Remember the letter A. Reply with A." --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05 -n spike-dup
    sleep 2
    run S14b -- -p "Remember the letter B. Reply with B." --output-format json "${COMMON_CHEAP[@]}" --max-budget-usd 0.05 -n spike-dup
    run S14c -- -p "Which letter did I ask you to remember? Reply with one letter." --output-format json \
        -r spike-dup "${COMMON_CHEAP[@]}" --max-budget-usd 0.05
fi

if want S15; then
    run S15 -- -p "Use the Agent tool exactly once (subagent_type Explore) to list the files in this project, then reply with the number of files." \
        --output-format json --model sonnet --effort low --strict-mcp-config --max-budget-usd 0.30
fi

if want S17; then
    run S17 SPIKE_SECRET=abc4711 -- -p "Run the command: printenv SPIKE_SECRET and reply with its exact output." \
        --output-format json --permission-mode dontAsk --allowedTools "Bash(printenv *)" "${COMMON_CHEAP[@]}" --max-budget-usd 0.10
fi

[ "$DRY" = 1 ] && exit 0

# Plan files the spike's plan-mode sessions wrote (their exact paths are in the hook logs) move out of
# ~/.claude/plans into the run's output, so the user's plan folder keeps only the user's plans.
mkdir -p "$OUT/plans"
grep -ho "$HOME/\.claude/plans/[A-Za-z0-9._-]*\.md" "$OUT"/*.hooks.log 2>/dev/null | sort -u | while read -r f; do
    [ -f "$f" ] && mv "$f" "$OUT/plans/"
done

# summary.tsv: name, rc, cost, subtype, is_error, top-level keys (json) or event types (stream-json)
python3 -I - "$OUT" <<'PY' > "$OUT/summary.tsv"
import json, os, sys
out = sys.argv[1]
print("name\trc\tcost\tsubtype\tis_error\tshape")
for f in sorted(os.listdir(out)):
    if not f.endswith(".out"):
        continue
    name = f[:-4]
    rc = open(os.path.join(out, name + ".rc")).read().strip() if os.path.exists(os.path.join(out, name + ".rc")) else "-"
    text = open(os.path.join(out, f)).read()
    docs = []
    try:
        docs = [json.loads(text)]
        shape = "json:" + ",".join(sorted(docs[0])) if isinstance(docs[0], dict) else "json"
    except ValueError:
        types = []
        for line in text.splitlines():
            try:
                d = json.loads(line)
            except ValueError:
                continue
            docs.append(d)
            t = d.get("type", "?") + ("/" + d["subtype"] if "subtype" in d else "")
            if t not in types:
                types.append(t)
        shape = "stream:" + ",".join(types) if docs else "text"
    res = next((d for d in reversed(docs) if isinstance(d, dict) and d.get("type") == "result"), docs[-1] if docs else {})
    if not isinstance(res, dict):
        res = {}
    print("\t".join([name, rc, str(res.get("total_cost_usd", "-")), str(res.get("subtype", "-")),
                     str(res.get("is_error", "-")), shape]))
PY
log "spent \$$(spent); summary: $OUT/summary.tsv"

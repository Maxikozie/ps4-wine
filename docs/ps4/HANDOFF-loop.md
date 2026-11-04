# Handoff: the loop harness

An unattended harness that runs milestones end to end:
- plan, review and revise;
- host tests, then console runs with no hands (install, launch, close, restart, buttons, logs, shots);
- verify, a bounded fix loop, the evidence, then the next milestone.

It stops at the human tasks below and reaches the user through ntfy.

**The approved plan** (revision 3, 2026-11-04) is
`/home/maxikozie/.claude/plans/pasted-content-id-196c-goal-build-memoized-piglet.md`. It holds every phase's
deliverables, rules and stop points. This file holds the state: what has been done, measured and decided,
and what comes next. Where this file settles a choice the plan left open ("per S3", "per S4", "if S9"),
this file wins.

## Status

| Phase | What | State |
|---|---|---|
| 0 | Spike: headless CLI semantics | **done 2026-11-04, at its stop point** (results below) |
| 1 | ctl ELF (BinLoader): install / launch / close; console run x1 | not started |
| 2 | Title control port (TCP 18195), heartbeat, LoadExec after the release; console run x2 | not started |
| 3 | netpad (UDP 18196), pad.sh; console run x3 | not started |
| 4 | `ps4ctl.sh`, the "adb" | not started |
| 5 | Watchdog and recovery | not started |
| 6 | `loop.sh` orchestrator, ntfy, human task registry (stop before any real session; the commit policy is chosen there) | not started |
| 6b | Dashboard, `dash.sh --serve` | not started |
| 7 | Guards (per-role PreToolUse hook) | not started |
| 8 | Host acceptance (fake claude, fake ps4ctl, fake ntfy), then the first real no-hands run | not started |

## How to continue

One phase per session; no session carries phases 0-8. Start a fresh session with:

```
Continue /home/maxikozie/.claude/plans/pasted-content-id-196c-goal-build-memoized-piglet.md at phase 1
(the ctl ELF and console run x1). Read docs/ps4/HANDOFF-loop.md first, then CLAUDE.md.
```

At each stop: update this file first (status, measurements, decisions, untested, files, next step), then
report, then end with the prompt for the next phase.

## Design in one screen

Decisions 1-10 of the plan, short:

1. **ctl commands** travel as a command block patched into the ctl ELF's bytes (magic, nonce, op,
   arguments). Results go to netlog and `/data/ps4-wine/ctl/<nonce>.txt`.
2. **The ctl ELF** lives in this repo (`ctl/`, GPL-3.0). It links libkernel/libc/libSceNet only and
   resolves every other libSce* call by load + dlsym, so a refused library fails one step and every step is
   logged. No code comes from flatz, PKG Sender, playden or nx-on-orbis.
3. **The control port and netpad** live in the fork's `ps4wine.prx` (our own LGPL code, upstream-clean).
   The stub eboot is not touched.
4. **One Python stdlib helper, `scripts/ps4/loopkit.py`,** handles JSON, the hook's stdin, ntfy and the
   dashboard. Control flow stays in bash.
5. **Hooks live in `.claude/settings.json`.** `loop-guard.sh` exits 0 in bash unless
   `PS4_LOOP_SESSION=1`, then applies the rules of `PS4_LOOP_ROLE` (`plan|review|propose|exec|verify`).
6. **The harness console steps get their own rules:** `check.sh x1` (ctl), `x2` (port + LoadExec after the
   release) and `x3` (netpad). Each is written with fixtures before its run.
7. **Install proof** is a package stamp (`/app0/assets/stamp.txt`). The title prints
   `PW_MS pkg_stamp= argv= pid=`.
8. **Marks stay human.** netpad sends XInput state only: no touchpad, no Guide, no Pause.
9. **ntfy:** one concrete action per request, with Done/Skip or Approve/Reject. Done only unblocks; the
   loop then verifies the action itself. Quiet hours default to 00:00-09:00, and a timeout parks the
   milestone.
10. **Parked means read-only.** While a milestone is parked, the loop only SELECTs, PLANs and REVIEWs the
    next one (marked provisional). Host work for another milestone happens in a worktree or not at all.

## Phase 0: the spike (2026-11-04)

**The script.** `scripts/ps4/loop-spike.sh` (`--help`, `--dry-run`, `--only`, `--budget`).
- It runs every item in a scratch project, `build/loop-spike/proj`: a fresh git repo with a logging and
  denying PreToolUse hook. This repo's session list and settings were not touched.
- Every child `claude` runs with the parent session's `CLAUDE*`/`AI_AGENT` variables and any `NTFY_*`
  removed, so it behaves as if started from a terminal.
- Plan files that its plan-mode sessions write are moved from `~/.claude/plans/` into the run's output.

**The runs.**
- Claude Code **2.1.318**; models haiku (cheap items) and opus (S3, S12, S13, S13c), effort low,
  `--strict-mcp-config`.
- Three runs:
  - `logs/loop/spike/run1`: every item, $1.61;
  - `run2`: S4, S5, S8, S13c and S15 re-measured, $0.75;
  - `run3`: S2d and S4d, $0.11.
- Total spent: **$2.47** (cap $3).

**Why run2 was needed.** run1's S5 cap ($0.01) was above the task's cost, so it never tripped. run1's S8
`sleep 30` was refused by Claude Code itself before it ran.

| # | Measured | Observed |
|---|---|---|
| S1 | `--output-format json` keys | `type, subtype, is_error, result, session_id, total_cost_usd, usage, modelUsage` (per model, with `costUSD` and `costBasis: "list"`), `num_turns, stop_reason, terminal_reason, permission_denials, subagent_stats, api_error_status, safety_stops, duration_ms`, ... |
| S2 | `--json-schema` | The object is in **`structured_output`**, and `result` holds the same JSON as text. Works with `--resume` (S2c). **An unsatisfiable schema ends `subtype: success`, `is_error: false`, with no `structured_output`**; the model explains in `result` (S2b). |
| S2d | `--tools Read,Grep,Glob` + `--json-schema` | Works: `StructuredOutput` is added on its own. |
| S3 | plan mode under `-p` | **There is no ExitPlanMode tool under `-p`.** The model writes its plan with `Write` to `~/.claude/plans/<random-slug>.md` (through the PreToolUse hook), may run read-only Bash, and ends `success` with the plan in `result`. `--permission-prompts none` and `host` behaved the same. With `--json-schema`, `structured_output` = `{plan, steps[]}` (S3c). |
| S4 | `--resume` with another mode, model and effort | **All three switch.** The `system/init` event shows `permissionMode: acceptEdits`, `model: claude-sonnet-5-5` after a plan-mode haiku start, and the resumed session wrote a file. Effort is not in `init`, but the hook input carried `effort.level: high`. |
| S4d | `--tools` on `--resume` | Switches: `init` listed `[Read]`, then 26 tools after `--resume ... --tools default`, and the write succeeded. |
| S5 | `--max-budget-usd` | **A tripped cap gives rc 1, `subtype: error_max_budget_usd`, `is_error: true`, `terminal_reason: budget_exhausted`, `result: null`.** The cap is checked after a turn: $0.00506 against $0.005. The session can be resumed afterwards. |
| S6 | errors | A bad model gives JSON `is_error: true`, `terminal_reason: api_error`, `api_error_status: 404`, rc 1. These give no JSON, only stderr and rc 1: a bad schema (`--json-schema is not valid JSON`), an unknown resume ID (`No conversation found`), a **reused `--session-id` (`Session ID ... is already in use`)**, and stream-json without `--verbose`. |
| S7 | refusal | not provoked; **untested** |
| S8 | signals during a running tool (python sleep) | **SIGINT: rc 0** with a result event `subtype: error_during_execution`, `terminal_reason: aborted_tools`; the tool is recorded as rejected. **SIGTERM: rc 143**, no result event; the tool's child died (exit 137 recorded). Both sessions resume with that context. A bare Bash `sleep N` is refused by Claude Code itself ("use Monitor ... or run_in_background"). |
| S9 | `--bg` | **`--bg` refuses `--print`** ("--print never starts the interactive session that `claude agents` attaches to"). It also needs workspace trust (the scratch project had none). Background sessions are interactive only, with no JSON result or cost. `claude agents --json` lists every interactive session on the machine. |
| S10 | stream-json | Needs `--verbose`. Events: `system/session_title_changed`, `system/init` (permissionMode, model, tools, cwd, session_id), `assistant` (text / tool_use), `user` (tool_result), `rate_limit_event`, `system/thinking_tokens`, `result`. |
| S11 | hooks | Project `.claude/settings.json` hooks fire under `-p`:<ul><li>in plan mode, including the plan-file `Write`;</li><li>inside subagents (the input carries `agent_id` and `agent_type`);</li><li>on `StructuredOutput` and `ToolSearch` calls.</li></ul>`--settings` hooks fire too. The hook inherits the session's environment (`PS4_LOOP_SESSION`, `PS4_LOOP_ROLE` seen). Deny by JSON `permissionDecision` and by exit 2 both work, both land in `permission_denials`, and the model goes on with its next step. The hook input includes `permission_mode` and `effort.level`. **Fast-path cost: 4.6 ms per call** (bash exits on the unset flag) against 11.8 ms when Python starts. |
| S12 | `--permission-mode auto --permission-prompts none` | **Nothing was refused**: a repo script, a file write, `git push origin main` (failed only for lack of a remote) and `rm -rf /tmp/...` all ran. Auto mode is not a guard for this project's rules. |
| S13 | tool restriction of subagents | **`--tools` reaches subagents:** a general-purpose subagent had only Read, Grep, Glob and Agent (S13a). **Plan mode does not:** a general-purpose subagent under plan mode listed Bash, Edit and Write (S13c). The plan-mode model declined to start a writing subagent (S13b), which is behaviour, not a guarantee. |
| S14 | duplicate `-n` | Allowed. Then **`-r <name>` fails with rc 1**: "matches 2 sessions", listing the IDs. |
| S15 | subagent cost | **Included.** The result's `modelUsage` equals the main transcript plus the subagent's (output 336 + 481 = 817, cache read 47584 + 17311 = 64895). An Explore subagent ran on the main model (sonnet). |
| S16 | usage/rate limit hit | not provokable; **untested**. The stream's `rate_limit_event` reports it ahead of time: `unifiedWindows.five_hour` and `.seven_day` `{utilization, resetsAt, status}`, plus `overageStatus: rejected` (`out_of_credits`). At 04:33 the windows stood at 0.16 (five hours) and 0.53 (seven days). |
| S17 | environment reaching tools | **Yes:** `printenv SPIKE_SECRET` printed it. Scrubbing must happen when the session starts. |

## What phase 0 settles (overrides the plan's open choices)

**PLAN**
- Plan mode plus `--json-schema` (`{plan, steps[]}` and the step fields of the plan) plus an explicit
  `--tools "Read,Grep,Glob,Agent,Bash,ToolSearch,WebSearch,WebFetch"`. The `--tools` list keeps the
  planner's research subagents tool-restricted, because plan mode alone does not (S13c).
- The prompt says ExitPlanMode is unavailable and the session ends by returning the structured output.
- loopkit reads `structured_output`. A missing `structured_output` is a stage failure, even with
  `subtype: success`: retry once with the model's `result` text quoted, then park.
- The plan file the session wrote (its path is in the stream and the hook input) is moved to
  `logs/loop/<m>/`.

**REVIEW, VERIFY, PROPOSE**
- Read-only `--tools "Read,Grep,Glob,Agent"` plus a schema; `--tools` restricts their subagents too.
- The guard's role rules are the second layer, because hooks also fire inside subagents.

**Guard**
- Every role must allow `StructuredOutput` and `ToolSearch`.
- "Its own plan file" for the `plan` and `propose` roles means the first `~/.claude/plans/*.md` path that
  session writes. The slug is random, so the guard records it per `session_id` and denies any other path.
- The fast path costs about 5 ms per tool call in the user's own sessions.

**EXECUTE**
- **Resume the planner** (`--resume <plan id> --permission-mode auto --tools default --effort <exec>`).
  Mode, model, effort and tools all switch on resume (S4, S4d), and the research context is kept.
- Fall back to a fresh `exec-<m>` session given the plan when the planner's context is above
  `EXEC_FRESH_ABOVE_TOKENS` (loop.conf).
- Auto mode refuses nothing relevant (S12), so the PreToolUse guard and VERIFY carry the rules.

**Session IDs and names**
- A new session gets `--session-id`. A stage re-run after a crash uses `--resume <id>` if the transcript
  exists: a reused `--session-id` is refused (S6).
- Names are unique per stage, round and attempt (`plan-<m>`, `review-<m>-r2-a`, `exec-<m>-a3`,
  `verify-<m>-a1`), because `-r <duplicate name>` fails (S14).
- The harness always resumes by ID; names are for the user's `claude --resume`.

**Exit and result typing**
- rc ≠ 0 with no JSON: a configuration error. Pause; no retry.
- `error_max_budget_usd`: the budget branch.
- `api_error`: retry once, then pause.
- `error_during_execution`/`aborted_tools`: interrupted (takeover or STOP).
- An unknown subtype or terminal reason: pause.
- rc 0 alone never means success: SIGINT gives rc 0.

**Watch and take over**
- Every session runs `-p --output-format stream-json --verbose`, teed to `logs/loop/<m>/<name>.jsonl`.
  `loop.sh watch` renders it.
- `loop.sh takeover` sends **SIGINT** (a clean result event; the tool is recorded as rejected), then
  prints `claude --resume <id>`.
- `--bg` is not used (S9).

**Budgets**
- Costs are list-price estimates (`costBasis: list`), subagents included (S15).
- The account runs on usage windows, so loop.conf adds two limits:
  - `FIVE_HOUR_MAX` (default 0.85): wait until `resetsAt`;
  - `SEVEN_DAY_MAX` (default 0.80): park everything and notify.

  Both are read from each session's `rate_limit_event`. The $ caps stay as a second meter.

**Executor prompts**
- Wait with the harness's own waits (`ps4ctl.sh wait-heartbeat`, `logs expect`), never a bare `sleep`.
  Claude Code refuses those (S8).

**Environment**
- `loop.sh` starts every session with `env -u` for `NTFY_*` and for the parent's `CLAUDE*`/`AI_AGENT`, in
  case the loop is started from inside a Claude session (S17).

## Not tested (phase 0)

- **S7** a refusal, and **S16** an actual rate-limit hit: neither could be provoked. Both fall into "unknown
  terminal state, pause".
- `--bg` with workspace trust: not run. The design does not use `--bg`.
- `claude attach`: interactive, not run.
- Whether a `-p` session holding a background subagent always waits for it before its result. S15's
  result came from the turn that the subagent's task notification started (`origin: task-notification`);
  only one case was seen.
- Hooks inside a subagent that writes. Only a read (Explore's Bash) was seen in a subagent.

## Console return codes

None yet. Phase 1 (x1) records LncUtil, AppInstUtil, SystemService, SysCore, UserService and Bgft here.

## Limits (defaults decided at phase 6's stop)

Per-session `--max-budget-usd`, a daily $ cap, `FIVE_HOUR_MAX`, `SEVEN_DAY_MAX`, launches per milestone,
launches per day, `FIX_ATTEMPTS_MAX`, review rounds (3), `PLAN_APPROVAL_FIRST_N` (2), quiet hours
(00:00-09:00) and the disk floor (20 GiB). Phase 0 cost $2.47.

## Human task registry (planned; `scripts/ps4/loop/human-tasks.json` lands in phase 6)

`tests/loop_registry_test.sh` will keep this table and the JSON equal. Each message is one concrete action.
Timeouts count waking hours only and always park the milestone; a timeout never fails it.

**Hands**

| ID | Trigger | Message (template) | Loop verifies after Done | Timeout |
|---|---|---|---|---|
| H1 | a ctl step is needed; 9090 closed, 2121 open | "BinLoader is off (port 9090 closed, FTP up). On the PS4: GoldHEN menu, enable BinLoader. Tap Done." | 9090 open and a `ctl.sh status` round trip | 12 h |
| H2 | watchdog: GPU hang, hang suspected, unreachable | "PS4 hung ({reason}). Hold power until it turns off, boot it, load GoldHEN, enable BinLoader, tap Done." | ICMP, 2121, 9090 up; `ctl.sh status` | 12 h |
| H3 | `shot --classify` sees a system dialog | "A system dialog is on the PS4 screen: \"{text}\". Press Cross on it with the DS4, then tap Done." | `shot --classify` shows no dialog | 12 h |
| H4 | an install under `CTL_INSTALL=manual` (only if x1 shows BinLoader may not install) | "Install {pkg}: close PS4 Wine (PS button, Options, Close Application), GoldHEN, Package Installer, /data/pkg/{pkg}, launch it, tap Done." | the port's `status` shows the new stamp | 12 h |
| H5 | x3, optional (build session) | "Press Cross once on the DS4 now (x3 override test, 60 s window)." | `netpad_overridden>0` | 60 s; untested otherwise |

H1 fires after each boot unless x1's follow-up shows BinLoader persists across a reboot.

**Eyes** (view.sh is opened first)

| ID | Trigger | Message (template) | Loop verifies | Timeout |
|---|---|---|---|---|
| E1 | a mark step in k or l | "{m}: {when to mark}. Click the right side of the touchpad once (or Pause on the USB keyboard). Tap Done." | the `PS4WINE {m}` line with `marks>=1` | 2 h |
| E2 | m's play step | frame "m: {what to play}. {when to mark}. {how long}. Tap Done after." | the m line, `gameplay=1 session_s>=300` | 24 h |
| E3 | n's play step | frame "n: {what to play}. {when to save, load and mark}. {how long}. Tap Done when finished." | the n line `saved=1 loaded=1 session_s>=1800`; a newer save over FTP | 24 h |
| E4 | a check that needs the user's word | "{m} check passed ({summary}). {question} Approve = yes, Reject = no, or type what was wrong." | the reply in the LOG notes; Reject → `FAIL (the user's word; check.sh PASS)` | 24 h |

E1-E3 text: the registry holds only the frame. The words come from MILESTONES.md's rule and the plan's
`human_text`, and D1 shows them before any play request goes out.

**Decisions**

| ID | Trigger | Message (template) | Loop verifies | Timeout |
|---|---|---|---|---|
| D1 | a plan for one of the first `PLAN_APPROVAL_FIRST_N` milestones; REVISE exhausted; a later milestone's first play request | "Plan for {m} (round {N}): {steps}; launches ≤ {L}; budget ${B}; you will be asked to: {human_text}. Approve / Reject (type why)." | the reply ID | 24 h |
| D2 | DONE: each commit (commits kept) or a reminder (commits off) | "Commit {m} {sub-step} to loop/{m}: {files}; MILESTONES note draft: {note}. Approve / Reject." | `git log` | 24 h |
| D3 | a CLAUDE.md draft | "CLAUDE.md draft ready ({topic}, diff on the dashboard). Approve = the harness git-applies it, uncommitted; Reject drops it." | `git diff CLAUDE.md` = the draft | none, one reminder |
| D4 | PROPOSE wrote candidates | "No milestone left after {last}. {N} candidate rows on the dashboard. Add the one you want to MILESTONES.md yourself, then tap Done." | a new row, neither passed nor parked | none, one reminder |
| D5 | a park with a summary | "{m} parked: {reason}. Reply with a note to retry, or Skip to leave it parked." | — | none |
| D6 | an executor `rule` step (m, n) | "New check rule for {m} (diff on the dashboard), implementing MILESTONES.md: \"{rule}\". Approve / Reject." | after git apply, the check.sh diff = the approved diff; the fixtures pass | 24 h |
| D7 | SELECT is ambiguous | "Next step? Candidates: {handoff sub-steps first, e.g. the ps5drv foreground patch, then rows, e.g. m}. Type the one to run." | the reply names a candidate | none |

Also the user's, and never asked by the loop on its own: unparking g, the commit policy, and the
build-time stop points (phase 0, x1, x2, x3, phase 6, host acceptance, the first real run).

## Files written so far

- `scripts/ps4/loop-spike.sh`: phase 0's spike. Re-run it after any Claude Code upgrade. `loop.sh` will
  refuse a CLI version other than the measured 2.1.318.
- `docs/ps4/HANDOFF-loop.md`: this file.
- Raw output in `logs/loop/spike/run{1,2,3}/` (gitignored): `NAME.{cmd,out,err,rc}`, hook logs,
  `summary.tsv`, and the four plan files the plan-mode items wrote.

## Next step

Phase 1, in a fresh session (prompt above):
1. Build the ctl ELF, `ctl.sh`, the `pkg_stamp`/pid start line, `check.sh x1` with fixtures, and the host
   tests.
2. Then the user enables BinLoader in GoldHEN and has the current PSWN00001 installed and running;
   `view.sh` is opened with the desktop entry's `--sink`.
3. Then one console run, x1: one LOG.md line, and a stop.

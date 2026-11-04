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
| 1 | ctl ELF (BinLoader): install / launch / close; console run x1 | **x1 run 1 FAIL 2026-11-04** (fSELF refused; plain ELF unbound in ScePartyDaemon). **BinLoader serves one connection per manual enable** (lifetime measured 16:37-16:42): the ctl cannot act without hands, so the loop takes **option 2** (manual installs, close/relaunch through phase 2). The resolver is not written |
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

## Phase 1: the ctl (2026-11-04, built and host-tested; x1 pending)

**Where the work is.** A worktree, `.claude/worktrees/loop-phase1` (branch `worktree-loop-phase1`, from
`f45fbef`), with its own clone of the fork at `third_party/prospero-win` (detached at `19bc0ca`, cloned with
`--reference` to the main fork). Nothing is committed (the user commits). The title was built there against
the main tree's `build/orbis-compat*`, `build/src/mesa-ps4` and the main fork's `.deps/wine-orbis/prx`
(read only; env overrides `ORBIS_COMPAT_BUILD`, `ORBIS_COMPAT_STAGE`, `MESA_SRC_DIR`, `WINE_PRX_DIR`).

**What BinLoader runs is unknown.** This changes the plan's picture. Nothing in this repo or `refs/`
documents GoldHEN's BinLoader, and its source is private ([GoldHEN](https://github.com/GoldHEN/GoldHEN):
"Project source code is currently private"). Its release notes say only "BinLoader Server on 9090 port"
and, in v2.4b17.3, "Improved BinLoader server (more payloads supported)". Two facts, both from
[orbisRPC](https://github.com/SirHumza/orbisRPC):
- **The fSELF form.** Its legacy OpenOrbis build (`scripts/build.sh`) links `crt1.o` with `link.x`,
  `-lc -lkernel ...` and `create-fself --eboot --paid 0x3800000000000011`. It then deploys the result as
  `/data/GoldHEN/payloads/orbisrpc.bin`.
- **The plain form.** Its shipping build is a ps4-payload-sdk ELF placed in `/data/payloads/`. Its
  `docs/BUILDING.md` says: "Never link `libkernel.so` (or any app-world `.so`). A spawned payload with
  unresolvable imports is SIGKILLed before `main()`". The allowed set is `libkernel_web.sprx`,
  `libSceLibcInternal.sprx`, `libSceNet.sprx` and `libSceSystemService.sprx`. The SDK's CRT also patches
  per firmware, which we must not do (no firmware offsets).

So the ctl comes in **two forms from one source**, and x1 finds out which one runs.

**The ctl** (`ctl/ctl.c`, `ctl/ctl_cmd.h`, `ctl/ctl_rt.c`; GPL-3.0; no code from another project)
- **Imports.** It uses no libc at all: it has its own formatter. It imports only libkernel (and libSceNet
  through `probes/probe_netlog.c`). LncUtil, SystemService, SysCore, AppInstUtil, UserService and Bgft
  are loaded with `sceKernelLoadStartModule` from `/system/common/lib/` and then `/system/priv/lib/`, and
  their calls are found with `sceKernelDlsym`. Every load and every missing symbol is logged.
  - The LncUtil calls are looked up in `libSceSystemService.sprx` first, then in a module named
    `libSceLncUtil.sprx` (whether that file exists is unknown).
- **The fSELF form** (`dist/ctl-<id>.elf`) is the probe's link without the pkg step: `crt1.o`, `link.x`,
  `libc.a`, `-lkernel -lSceNet`. `ctl.sh` patches a copy, then runs `create-fself --eboot` on it. The
  block survives `create-fself` (one magic in the `.bin`, checked on every send).
- **The plain form** (`dist/ctl-plain-<id>.elf`) has its own `_start` (its argument is ignored). It is
  an ET_DYN with no `PT_INTERP`, `-z now`, page-aligned segments, and GLOB_DAT relocations only
  (`-fno-plt`). Its two DT_NEEDED entries are generated stubs with sonames `libkernel_web.sprx` and
  `libSceNet.sprx`. `build.sh ctl` refuses any other NEEDED list and any raw `syscall`.
- **Steps and lines.** hello (pid, `sceKernelGetAppInfo`, the sandbox word, the /data result file),
  load/dlsym, init, user, bigapp (both proofs), exists, then the op. The result file is
  `/data/ps4-wine/ctl/<nonce>.txt`, fsync'd after every line. hello and done also go to klog.
  - `getprogname` is not in libkernel's stub, so the process name is not logged. hello's `app_title`
    and `sandbox` stand in for it.
- **Calls whose arguments are a guess** (the facts used are written in `ctl.c`):
  - `sceAppInstUtilAppInstallPkg(path, MetaInfo*)`: six string pointers, `uri` = the package, the content
    ID, the name "ps4-wine", the rest empty.
  - `LncAppParam{32 bytes, user, 0, 0, SkipSystemUpdate}`.
  - `sceSystemServiceKillApp(app, -1, 0, 0)`, used as the fallback when `sceLncUtilKillApp` fails.
  - `sceSystemServiceLaunchApp(title, argv, param)`, used as the fallback when `sceLncUtilLaunchApp` fails.
  - `sceLncUtilGetResultKillApp(app)`: its return code is logged only.
  - `sceAppInstUtilGetInstallProgressInfo(content_id, ...)`: polled for at most 300 s. The run ends when
    the task disappears after it was seen, at 100 %, or after 10 s without a task; then `AppExists`
    decides the result.

**Safety (compiled in, each one tested on the host).**
- **Kill** needs `proof_info` (SysCore's title ID of the big app) or `proof_lnc` (`GetAppId(PSWN00001)`
  equals the big app), and no contrary proof. It is refused with `same_pid` (the block's title pid is
  ctl's pid) and with `same_app` (ctl's own app ID is the big app's).
- **Install** needs `GetTitleIdFromPkg` = PSWN00001 and the title not running.
- **Launch** starts PSWN00001 only: the title ID is compiled in, never taken from the block.
- **cycle/probe** stop at the first step that fails.

**`scripts/ps4/ctl.sh`** (`--help`)
- **Commands.** `status|kill|install PKG|launch ARGS|cycle PKG ARGS|probe PKG` and `judge`.
- **Options.** `--form self|elf|auto`. With auto, the form cached in `build/ctl/form` is used. With no
  cached form, a status is sent in each form, fSELF first, and the first form that says hello is cached.
  Other options: `--log`, `--title-pid` (default: the newest `PW_MS ... pid=` in the log),
  `--console-dry`, `--patch-only`, `--dry-run`, `--print-layout`.
- **Packages.** A local `.pkg` is uploaded to `/data/pkg/` with `ftp_put`, and its size is checked first.
- **Waiting.** It waits for hello (20 s), then for done, in the log and in the result file over FTP.
- **Exit codes** as in the plan (0/2/3/4/5, plus 1 for usage).
- **probe** waits up to 120 s for the relaunched title's `PW_MS pkg_stamp=`. It then appends
  `PS4WINE x1 ctl ...` (host tag `H`) with `dialog=unjudged`.
- **judge** `--dialog 0|1 --shot FILE` appends the line again with the verdict, `dialog_by=eye`. No
  classifier for system dialogs exists before phase 4's `shot --classify`, so the x1 frame is judged by eye.

**Other files**
- `common.sh`: `ftp_put/ftp_get/ftp_size/ftp_rename` with `--max-time` (`PS4_FTP_BASE=file://` for
  tests). `deploy.sh` uploads through `ftp_put`, and `--install` exits 2 ("use ctl.sh install").
- `pkg.sh` writes `assets/stamp.txt` (`<UTC>Z-<build id>`, one token) into every package, plus
  `dist/<pkg>.stamp` beside it.
- Fork `native/orbis/wine64_main_orbis.c`: one `PW_MS pkg_stamp=<stamp> argv=<a,b> pid=<n>` line at
  start, on every sink (klog, netlog, diagnostics). The fork does not name this repo.
- `check.sh x1` passes on `hello=ok kill=ok install=ok launch=ok stamp_match=1 dialog=0`. It accepts
  the host tag `H`.

**Host tests** (`build.sh probe-test`, exit 0 on 2026-11-04)
- `tests/ctl_test.sh` (66 cases):
  - `ctl.c` built for the host with `tests/ctl_fake_console.c` (UBSan, no recovery): every refusal,
    the overwrite sequence, the SystemService fallbacks, and the stop of a cycle;
  - `ctl.sh`'s offsets against the header (`tests/ctl_block_dump.c`), patching, refusals (0 or 2 magics,
    a 64-byte argument, 9 arguments, bad paths), `--dry-run`;
  - end to end through a fake BinLoader that runs the host-built `ctl.c` on the patched payload:
    exit codes 0/2/3/4/5, upload, the auto form and its cache, `probe` → `check.sh x1` FAIL (unjudged)
    → `judge` → PASS, and a stale stamp.
- `tests/check_x_test.sh`: 9 fixtures.

**Not tested before x1** (x1 measures them):
- what BinLoader does with either form;
- the process the ctl gets, and whether it may load the system libraries and call LncUtil and
  AppInstUtil;
- every return code;
- whether `AppInstallPkg` takes a /data path, and whether a reinstall needs PrepareOverwrite;
- whether the title starts with `--ctl-x1`.

Not covered by x1 at all: whether BinLoader stays enabled after a reboot.

### The x1 run (procedure)

1. **The user.** Power the PS4 on, load GoldHEN, and enable FTP, klog and **BinLoader**. Launch PS4 Wine,
   the installed PSWN00001, and leave it running. Claude has `view.sh` open (the desktop entry's
   `--sink`).
2. **Claude.**
   - Check that 2121, 3232 and 9090 are open.
   - Start the log first, in the main checkout's logs dir:
     `LOGS_DIR=/home/maxikozie/ps4-wine/logs systemd-inhibit --what=sleep scripts/ps4/logs.sh --label x1 &`.
   - Then run `scripts/ps4/ctl.sh --log <that file> probe dist/ps4-wine-19bc0ca+dirty.pkg` (auto form). It
     uploads the package, sends a status in the fSELF form (and the plain form if that one is silent),
     then the probe.
3. **The frame.** Close the viewer (`pgrep -x` PID), take `shot.sh` within ~5 s of the relaunch, and
   reopen the viewer. Look at the frame, then run `ctl.sh judge --log ... --dialog 0|1 --shot ...`.
4. **The record.** `check.sh x1 --log ...`, then one LOG.md line. The return codes go into the table below.
5. **If neither form says hello:** H1/H2 do not apply (the console answered FTP). Record x1 as FAIL
   with what 9090 did (nc's reply bytes are kept beside the payload in `build/ctl/send/`), and stop.
   The user then chooses the second run (the plan's Bgft / RPI options), or `CTL_INSTALL=manual`.

### x1, first run (2026-11-04 16:11-16:18, LOG.md: FAIL; `logs/20261104-161137-x1.log`)

The title (`efdfeae+dirty`, plan l) ran as PSWN00001 throughout. The package was uploaded but not
installed. What was measured:
- **BinLoader 9090 closes.** It was open at 16:11:30, when the port watcher made **one empty connection**
  (`nc -z`). It was closed by 16:12:08, while FTP and klog stayed up. Either BinLoader serves one
  connection and stops, or it stopped when the title launched at 16:11:56. Not settled. The user
  re-enabled it by hand before each send. `ctl.sh` no longer checks the port before a send; the send's
  own connection decides (exit 4 when nc fails).
- **fSELF rejected.** The fSELF form (`create-fself --eboot`, 92272 B) was refused on screen: "invalid
  payload format". orbisRPC's legacy route does not apply to 9090.
- **Plain ELF accepted, imports never bound.** The plain ELF form (57104 B, ET_DYN, NEEDED
  `libkernel_web.sprx` + `libSceNet.sprx`) was accepted and ran in a **new process, `ScePartyDaemon`**.
  - Modules loaded there: `libkernel_sys.sprx` (no `libkernel_web`), `libSceLibcInternal`,
    `libSceSysmodule`, `libSceNet`, `libSceNetCtl`, `libSceSystemService`, `libSceUserService`,
    `libSceRegMgr`, `libSceNpManager`, AudioOut and others. Paths were under the sandbox word
    `/AsQonIClUj/common/lib/`; the eboot is `/app0/eboot.bin`.
  - It faulted at **rip=0** (BrF 0x5a48, the only backtrace entry 0x832984043 in libkernel_sys's text),
    with every argument register 0. No hello and no result file followed. The loader bound none of the
    imports, so the first call through the GOT went to 0.
- **The console was unharmed.** PS4 Wine kept running, and klog printed GoldHEN's "copyin: GoldHENLoader
  has nonsleeping lock" in the middle of the dump.

**What it means.** GoldHEN's loader runs ELFs in the ScePartyDaemon process, as ps4-payload-sdk payloads
are run. It does not do the dynamic linking our ELF needs: the payload (its crt) must find its own
imports. How the SDK's crt does that, and what the loader passes to the entry point, is the open
question. A research subagent for it was **stopped by the API's cyber safeguards**, and the answer was
not looked up in this session.

**Stop (user's choice).**
1. **The user supplies the convention.** For example, put a checkout of the PS4 payload SDK under
   `refs/` (read only; the user adds it), or point to its documentation of the entry arguments and
   import resolution. The ctl's plain form then gets its own small import resolver, our code, with no
   firmware offsets. The firmware-gated parts of that SDK's crt are out of bounds (CLAUDE.md: no
   exploit work, no firmware-specific kernel offsets).
2. **Skip BinLoader.** Use `CTL_INSTALL=manual` (registry H4) for installs. Move closing and relaunching
   into the title itself, which is phase 2's control port: a LoadExec restart covers "launch again". Only
   the kill of a hung title then needs hands (H2).
3. **Bgft or flatz's RPI**, the plan's second-run options. Both still need a process that can call
   them, so they depend on 1 or on the title.

### Option 1 chosen (2026-11-04): what the references say

The user added two read-only references (not touched here):

| Checkout | Commit | Licence |
|---|---|---|
| `refs/ps4-payload-sdk` (Scene-Collective) | `b7326416c23ce14639e9180a24093bdc5eedb579` (main) | **no top-level licence**; some files GPL-2.0-only (`libPS4/source/pfs.c`), which cannot go into GPL-3.0 code: **facts only** |
| `refs/elfldr` (Al-Azif's fork of John Törnblom's PS4 ELF loader) | `990674670275b774350abb8e374c768334866c80` (master) | GPL-3.0-or-later (README, file headers) |

The userland convention, as facts:
- **The SDK's payloads link statically.** They have no DT_NEEDED and no loader-bound imports.
  `libPS4/crt0.s` is `_start: jmp _main`, and the entry's arguments are not used.
- **libPS4 finds every function itself, with two raw syscalls** (`libPS4/source/syscall.s`:
  `mov r10, rcx; syscall`):
  - 594, `loadModule(name, 0, &handle, 0)`. `initKernel` tries `libkernel.sprx`, then
    `libkernel_web.sprx`, then `libkernel_sys.sprx`.
  - 591, `getFunctionAddressByName(handle, "name", &addr)`.

  Other modules are then loaded by name with the resolved `sceKernelLoadStartModule`, and their functions
  found with 591 (`RESOLVE(module, name)`).
- **elfldr (`elfldr.c`)** maps the PT_LOAD segments and applies **only `R_X86_64_RELATIVE`**. It sets
  `rip` to the entry and aligns `rsp` (`rsp &= ~0xf; rsp -= 8`). Nothing in the part read sets an argument
  register.

That explains run 1: our GLOB_DAT imports were never bound. A ctl that works under this convention is a
static PIE with RELATIVE relocations only, which finds libkernel through 594/591.

**Not done, and why.** The API's safety classifier stopped this session while it read further into
elfldr (the part after process setup). The session therefore did not write the resolver, and did not
run the planned zero-import entry-register stage, the raw-syscall check in ScePartyDaemon, or the
BinLoader lifetime measurements (items 2-4 of the user's list). Only item 5 was done: `check.sh x1`
now counts only a klog crash dump ("# proc name:" / "# reason:") as CRASH, and a live title's handled
Wine error is not a crash (fixtures `x1-wineerr.log`, `x1-ctlcrash.log`). Run 1's log now checks as
`CRASH | crash dump: ScePartyDaemon: page fault ...`.

### BinLoader's lifetime (2026-11-04 16:37-16:42, LOG.md RECORDED; `logs/20261104-164039-x1-binloader.log`)

Each check was exactly one `nc -z -w3 192.168.8.184 9090`, and nothing else touched 9090.

| Check | Time | State before | Result |
|---|---|---|---|
| a1 | 16:39:05 | enabled at the home screen at 16:37, idle | **open** |
| a2 | 16:40:05 | 60 s after a1, still at the home screen | **closed**: a1's one empty connection turned it off |
| c | 16:41:07 | re-enabled by hand, PS4 Wine launched (start line 16:41:06) and running | **open**: a launch does not close it |
| d | 16:42:19 | 30 s after PS4 Wine was closed (16:41:49), not re-enabled | **closed**: closing the app does not re-arm it |

**Conclusion.**
- GoldHEN's BinLoader **serves one connection per enable**. Any connection uses it up, an empty one
  included, whatever app runs. It is not tied to the home screen: it stays open while a title runs
  (c). Run 1's closure at 16:12 was the port watcher's empty connection, not the title's launch.
- A ctl therefore **can act, but only once per enable, and the enable is the user's hands**.
  - It can act from the home screen and while PS4 Wine runs. A kill is possible in principle.
  - It cannot act unattended: every send needs H1 ("enable BinLoader") first.
- Not measured:
  - Whether a payload, rather than an empty connection, also uses BinLoader up. In run 1 each of the two
    sends followed a re-enable, so it was never seen. A one-shot server likely treats both alike; the
    first resolver run will show it.
  - The plan's state b ("60 s after a payload at the home screen").
  - Whether a reboot keeps BinLoader enabled.

**What it means for option 1 vs option 2.**
- **Option 1 saves the loop no hands.** A no-hands kill, install or relaunch through the ctl costs one
  manual enable each. That is the same effort as H4's manual install, with the extra risk of an
  undocumented loader. Its only gain is turning "install by hand" into "enable by hand", and that is
  not worth finishing the resolver for the loop.
- **Option 2 is the loop's path.**
  - Installs are manual (`CTL_INSTALL=manual`, H4).
  - Close and relaunch move into the title (phase 2's control port, LoadExec after the release).
  - A hung title needs hands (H2, a power cycle anyway).
- **The registry and watchdog follow from that (to apply in phase 6):**
  - H1 stops being "BinLoader is off": nothing in the loop needs BinLoader.
  - H4 becomes the normal install route.
  - The watchdog never connects to 9090. A probe would use the server up: no port watcher on 9090,
    ever.
- **Kept for manual use.** The ctl stays a manual tool. `ctl.sh` sends once (no pre-check), and its
  exit 4 means "enable BinLoader".

## Console return codes

None yet: no system call of the ctl ran (x1 run 1 faulted before its first import). Recorded so far:
GoldHEN BinLoader's on-screen "invalid payload format" for an fSELF.

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
- Phase 1 (uncommitted, in the worktree):
  - new: `ctl/ctl.c`, `ctl/ctl_cmd.h`, `ctl/ctl_rt.c`, `scripts/ps4/ctl.sh`, `tests/ctl_test.sh`,
    `tests/ctl_fake_console.c`, `tests/ctl_block_dump.c`, `tests/check_x_test.sh`, `tests/fixtures/x1-*.log`;
  - changed: `build.sh` (target `ctl`, two tests in `probe-test`), `check.sh` (`x1`, the `H` tag),
    `common.sh` (FTP helpers), `deploy.sh` (no `--install`), `pkg.sh` (the stamp), and this file;
  - the fork's `native/orbis/wine64_main_orbis.c` (the start line);
  - built: `dist/ctl-f45fbef+dirty.elf`, `dist/ctl-plain-f45fbef+dirty.elf`, and
    `dist/ps4-wine-19bc0ca+dirty.pkg` (stamp `20261104T041616Z-19bc0ca+dirty`).
  - Fork `make test`: exit 0.

## Next step

Phase 2 is the loop's path (BinLoader's lifetime above): the title's control port, heartbeat and LoadExec
after the release (console run x2). In phase 2 or 6, the registry changes with it: H4 becomes the normal
install route, H1 is dropped, and nothing in the loop ever connects to 9090. The ctl stays a manual
tool. Its import resolver is not needed for the loop; a later session may still write it from the facts
in "Option 1 chosen".

```
Continue /home/maxikozie/.claude/plans/pasted-content-id-196c-goal-build-memoized-piglet.md at phase 2
(the title control port, heartbeat, LoadExec after the release; console run x2). Read docs/ps4/HANDOFF-loop.md first, then CLAUDE.md.
```

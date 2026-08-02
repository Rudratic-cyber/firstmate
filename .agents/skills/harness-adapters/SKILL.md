---
name: harness-adapters
description: Agent-only reference for firstmate harness operations. Use before spawning or recovering a crewmate or secondmate, handling a trust dialog, sending a harness-specific skill invocation, interrupting or exiting an agent, resuming an exited agent, or verifying a new harness adapter. Contains verified facts for claude, codex, opencode, pi, pi-signed, grok, kimi, cursor, and antigravity.
user-invocable: false
metadata:
  internal: true
---

# harness-adapters

Use this reference before any harness-specific firstmate operation: spawn, recovery, trust-dialog handling, skill invocation, interrupt, exit, resume, or adapter verification.

Crewmates default to the same harness firstmate is running on unless `config/crew-harness` records an adapter name.
Optional dispatch profiles in `config/crew-dispatch.json` can override that static default for one crewmate or scout dispatch by selecting concrete harness, model, and effort axes at intake.
When a matched rule or default is a profile array, load `quota-array-dispatch` for the completion-aware candidate choice after this skill establishes harness and model/provider facts.
The captain may override that file at session start or later; a per-task instruction such as "run this one on codex" overrides it for that dispatch only.
`default` means mirror firstmate's own harness.

Secondmates have their own harness knob, so a secondmate can run on a different adapter than crewmates.
`config/secondmate-harness` is the harness the primary uses to launch SECONDMATE agents, resolved through the fallback chain `config/secondmate-harness` -> `config/crew-harness` -> firstmate's own.
An absent or `default` `config/secondmate-harness` therefore behaves exactly as the crew harness did before this knob existed (secondmates launched on the crew harness); setting it splits the two.
The [`secondmate-provisioning` skill](../secondmate-provisioning/SKILL.md) owns the complete inherited-local-material allowlist and propagation contract.
This skill owns only the harness-relevant consequence: a secondmate's own crewmates use the primary's inherited dispatch profiles and static harness value, while `config/secondmate-harness` is the primary's own setting and is never inherited - secondmates do not spawn secondmates.
Inheritance copies the literal `config/crew-harness` file, so for a secondmate's own crewmates to run on the primary's crewmate harness the captain must set `config/crew-harness` to a concrete adapter name, such as `codex`.
If `config/crew-harness` is unset or `default`, there is no concrete value to inherit, so the secondmate's own crewmates fall back to the secondmate's own/detected harness rather than the primary's effective crewmate harness.
Inheritance also copies the literal `config/crew-dispatch.json` file, so secondmates apply the same best-fit profile rules for their own crewmates.

Each adapter splits into mechanics and knowledge.
The per-task mechanics, including launch command, autonomy flag, and any enabled crewmate turn-end hook, live in `bin/fm-spawn.sh`.
The primary-session "no turn ends blind" guard contract and harness hook installation paths live in `docs/turnend-guard.md`.
The primary-session watcher wake protocols are rendered from `docs/supervision-protocols/` by `bin/fm-supervision-instructions.sh`.
The supervision knowledge lives here: busy state, exit command, interrupt, dialogs, resume behavior, skill invocation, and quirks.
Each adapter's `Busy state` row names only which semantic source that harness uses; `bin/fm-busy-lib.sh` owns the contract itself, including verdicts, source attribution, and the verification gates that keep an unverified harness at unknown.

Never dispatch a crewmate or secondmate on an unverified adapter.
If `config/crew-harness` or `config/secondmate-harness` names an unverified adapter, tell the captain under `AGENTS.md` section 9 that the requested worker runtime is not verified yet, use firstmate's own verified runtime for current work, and ask only whether to verify the requested runtime before future use.
Do not pause current work for that future-verification choice, and never launch an unverified adapter.
If the captain asks for a new harness, propose verifying it first: spawn a trivial supervised task using `fm-spawn`'s raw-launch-command escape hatch, confirm every fact empirically, then record the mechanics in `fm-spawn`, its semantic busy source and trust gate in `bin/fm-busy-lib.sh`, any needed `FM_COMPOSER_IDLE_RE` empty-composer override plus any novel bare agent prompt glyph in `bin/fm-composer-lib.sh`'s shared composer classifier (the one fleet-wide owner of the empty/dead-shell/pending decision, so a new harness's own idle composer is not misread as a dead shell), the tmux agent-process liveness classification in `bin/backends/tmux.sh` when the harness can launch a secondmate, and the verified knowledge here.

## Detection

`bin/fm-harness.sh` prints firstmate's own harness, using verified env markers first and then process ancestry.
Within the Pi family, only the exact launch-boundary marker `FM_PI_HARNESS=pi-signed` alongside `PI_CODING_AGENT=true` selects the signed identity; unmarked shared launcher ancestry remains `pi`.
`bin/fm-harness.sh crew` resolves the effective crewmate harness from `config/crew-harness` (absent or `default` -> own).
`bin/fm-harness.sh secondmate` resolves the secondmate-launch harness through the chain `config/secondmate-harness` -> `config/crew-harness` -> own, so an unset `config/secondmate-harness` matches the crew harness.
`bin/fm-spawn.sh` uses `crew` mode for a crewmate/scout launch and `secondmate` mode for a `--secondmate` launch, re-resolving on every spawn so the split is durable across respawns; an explicit per-spawn harness arg overrides either.
On `unknown`, ask the captain instead of guessing.
A captain override always beats detection.
When verifying a new adapter, record its env marker and command name in `bin/fm-harness.sh`.

For stuck recovery, the target window's harness is recorded as `harness=` in `state/<id>.meta`.
Use that value for interrupt, exit, resume, and skill-invocation facts.

## Primary turn-end guard

The primary integrations for `claude`, `codex`, `opencode`, `pi`, `pi-signed`, and `grok` have empirically validated hook paths for the "no turn ends blind" guard.
`claude` and `codex` block directly through Stop hooks that preserve exit status 2 and stderr from `bin/fm-turnend-guard.sh`.
`opencode`, `pi`, and `pi-signed` expose passive lifecycle callbacks and force one bounded follow-up when the shared predicate blocks.
Grok selects native blocking or its pre-native bounded resume fallback from the exact running Stop payload; [`docs/turnend-guard.md`](../../../docs/turnend-guard.md) owns that contract.
Kimi is outside the primary turn-end guard scope, while `docs/turnend-guard.md` owns its separate guarded global hook for crew wake signals.
The exact hook files, commands, scoping rules, and fail-open tradeoffs are owned by `docs/turnend-guard.md`.
`docs/verification/supervision.md` "Turn-end guard" owns active validation evidence.
When changing any primary turn-end hook, validate the real harness behavior in a scratch project or throwaway home before trusting it, then update that doc and the relevant concise fact below.

## Primary pre-arm (PreToolUse) seatbelt

The primary integrations for `claude`, `codex`, `opencode`, `pi`, `pi-signed`, and `grok` also have wired PreToolUse-equivalent hooks that deny a watcher-arm anti-pattern (shell `&`, truncating pipe, bundling, broad `pkill -f fm-watch`) before it runs.
`claude` and `codex` block directly through PreToolUse hooks; `grok` blocks the same way but requires every `$VAR` reference in its hook `command` string to carry an inline `:-default` or it fails to launch the hook entirely.
`opencode`, `pi`, and `pi-signed` block by throwing from `tool.execute.before` / returning `{block: true}` from `tool_call`.
The exact hook files, commands, output-shaping quirks (Claude Code only honors the deny when stdout is empty), and validation transcripts are owned by `docs/arm-pretool-check.md`.
When changing any watcher-arm PreToolUse hook, validate the real harness behavior in a scratch project before trusting it, then update that doc.
## Primary delegation-shape guard

Claude exposes built-in delegation, scheduling, and worktree tools that a primary session can use to create work with no `state/<id>.meta`, which makes the whole guard stack inert because every guard counts that metadata.
The shipped mechanism is `bin/fm-subagent-pretool-check.sh`, a primary-home PreToolUse guard that denies a delegation-SHAPED tool name.
Claude primaries should also use an untracked per-home local `permissions.deny` list as hardening for known Claude delegation tools, because it removes them from the model's schema so they are never offered.
That deny list must not ship in tracked `.claude/settings.json` because it is Claude-only rather than harness-agnostic, and because tracked project settings propagate into linked worktrees where they disarm legitimate crewmates.
`docs/subagent-guard.md` owns the full contract, the local deny-list recommendation, the `FM_ALLOW_SUBAGENT=1` escape hatch, and the per-harness applicability review.

Two verified facts worth pinning here.
The subagent tool presents to the model as `Agent`, and on Claude Code 2.1.217 both `Agent` and `Task` work as `permissions.deny` keys, verified by an A/B with a nonsense-name control.
`permissions.allow` is a pre-approval list rather than an availability list, so there is no fail-closed positive allowlist.

## Primary session-start nudge

AGENTS.md section 3 remains the behavioral owner for session start, while tracked native adapters invoke `bin/fm-sessionstart-nudge.sh` as an idempotent enforcement layer.
The wrapper prints one canonically typed `session-start` instruction to run `bin/fm-session-start.sh`; it never runs the digest, wake drain, bootstrap sweeps, lock, or supervision arm itself.
Full mechanics, scoping, and fail-open behavior live in `docs/sessionstart-nudge.md`.
`docs/verification/supervision.md` "Native session-start delivery" owns active dated commands, payloads, and evidence.

- `claude`: verified native `SessionStart` stdout injection; `.claude/settings.json` matches `startup`, `resume`, and `clear`, but not `compact`.
- `codex`: verified on 0.144.4; `.codex/hooks.json` receives `source=startup`, and wrapper stdout reaches model context.
- `opencode`: verified on 1.17.18; `session.created` plus `client.session.promptAsync` starts the nudge turn in the TUI, while `opencode run` remains fail-open headless.
- `pi` and `pi-signed`: verified native `session_start`; the existing primary extension handles `startup`, `new`, and `resume` and uses `pi.sendMessage` to inject context without racing a positional launch prompt.
- `grok`: the 0.2.103 project `SessionStart` event fires with `source=new`, but stdout does not reach model context; the tracked project hook remains fail-open, and a global token-guarded fallback requires a captain decision.

## Primary watcher supervision

At session start, `bin/fm-session-start.sh` prints exactly one watcher supervision block for the detected primary harness.
Do not substitute another harness's wait shape when resuming supervision.
Claude's Stop `asyncRewake` hook (`bin/fm-claude-stop-autoarm.sh`) owns tokenless re-arm around `bin/fm-watch-arm.sh`, and Grok uses tracked background-notify cycles around `bin/fm-watch-arm.sh`.
Codex uses bounded foreground checkpoints through `bin/fm-watch-checkpoint.sh` because Codex cannot reason while a foreground tool call is running.
OpenCode uses `.opencode/plugins/fm-primary-watch-arm.js`, which coordinates with the turn-end guard plugin and wakes the TUI with `client.session.promptAsync`.
Pi and pi-signed use the tracked `.pi/extensions/fm-primary-turnend-guard.ts` plus the tracked `.pi/extensions/fm-primary-pi-watch.ts`, both project-local extensions the Pi engine auto-discovers once trusted.
When changing any primary watcher adapter, update `docs/supervision-protocols/`, `docs/turnend-guard.md` if a shared idle or turn-end hook changed, and the relevant concise fact below.

## Launch profile axes

`bin/fm-spawn.sh` accepts concrete `--harness`, `--model`, and `--effort` values chosen by firstmate at intake.
Do not make the shell scripts parse or match natural-language dispatch rules.

Effort precedence is an explicit per-task captain instruction first, then any applicable standing dispatch profile or secondmate pin, then the generic fallback below.
Never replace an effort value supplied by either higher-precedence source.
Use the fallback only when neither the captain nor applicable standing configuration specifies effort.
Use `low` for well-understood work with an explicit bounded path and `xhigh` for ambiguous investigation or design.
Choose intermediate levels proportionally as complexity, uncertainty, blast radius, or open-ended reasoning increases.
When a verified adapter lacks `xhigh`, cap the choice at its highest supported non-`max` level rather than omitting the intended effort silently.
Never select `max` from this fallback; use it only when the captain has explicitly expressed that per-task or standing preference.

The supported launch-profile flags below are verified locally; each row records its evidence.

| Harness | Model flag | Effort flag | Notes |
|---|---|---|---|
| claude | `--model <model>` | `--effort <low\|medium\|high\|xhigh\|max>` | Verified on Claude Code 2.1.196. |
| codex | `--model <model>` | `-c 'model_reasoning_effort="<low\|medium\|high\|xhigh>"'` | Verified on codex-cli 0.142.1. The installed binary schema contains `model_reasoning_effort`, the active config uses it, and the bundled model catalog advertises only low/medium/high/xhigh. `max` is omitted. |
| grok | `--model <model>` | `--reasoning-effort <low\|medium\|high>` | Verified on grok 0.2.99 (2026-07-13). `--effort` is an alias, but firstmate's profile axis is reasoning effort. As of 0.2.99 the ceiling is `high`; both `xhigh` and `max` are rejected with `use one of: high, medium, low`, so firstmate omits them. |
| pi / pi-signed | `--model <model>` | `--thinking <low\|medium\|high\|xhigh\|max>` | Verified 2026-07-27 on Pi and pi-signed 0.82.0. Both expose the same accepted thinking levels and completed the same model-qualified max-thinking smoke. |
| opencode | `--model <provider/model>` | none for firstmate's interactive launch | Verified on opencode 1.17.6. `opencode run` has `--variant`, but firstmate launches the interactive `opencode --prompt` path, which has no verified effort flag. |
| kimi | `--model <model>` | none | Verified 2026-07-25 on Kimi Code CLI 0.29.1. |
| cursor | `--model <model>` | none | Verified 2026-08-02 on cursor-agent 2026.07.23-e383d2b. Effort is encoded IN the model id (e.g. `claude-opus-5-thinking-high`), not a separate axis: `--model 'base[effort=high]'` bracket-parameter overrides documented in `--help` were tested and rejected outright ("Cannot use this model: ..."). Firstmate resolves the intended effort into the chosen `--model` value at intake; a separately requested `--effort` stays recorded in task metadata and is never honored by a flag. **Captain-decided standing rule: every dispatch MUST use `--model auto` (or omit `--model`) until a Pro-tier named-model turn is confirmed - see the Cursor section below.** |
| antigravity | `--model <model>`, MUST precede `-i` | none (exists but unsafe) | Verified 2026-08-02 on agy 1.1.9. A `--model` flag placed AFTER `-i "<prompt>"` is silently ignored (verified: the session ran on agy's own last-used default instead); fm-spawn places `--model` before `-i` for this reason. agy exposes a real `--effort low\|medium\|high` flag, unlike cursor, but it was verified live to silently corrupt `--model` resolution when both are passed together (a named Claude model reverted to agy's default Gemini with no error; a `-low` Gemini model silently became `-medium`). Firstmate resolves the intended effort into the chosen `--model` value at intake instead, exactly like cursor - see the Antigravity section below. |

The concrete `harness` field owns adapter identity independently of the model provider: `harness=pi` with `model=xai/grok-*` is Pi using xAI, not `harness=grok`, and does not require Grok CLI login; `harness=grok` remains the standalone Grok Build CLI adapter.
No script resolves that split for you: establish which credential store a tuple reads from the discovery surfaces below plus `quota-axi auth --json`'s per-provider sources, and show that reasoning rather than inferring it from a harness, model, or source name.

### Model support discovery

Treat model and provider knowledge as current source-of-truth discovery, not as a permanent namespace or provider mapping.
Use the discovery surface in the current authenticated environment because supported and available models can change by version, account, and configuration.

| Harness | Authoritative discovery surface |
|---|---|
| claude | Open the current interactive session's `/model` picker; `claude --help` documents the accepted alias or full-model-name input shape. |
| codex | Open the current interactive session's `/model` picker. |
| opencode | Run `opencode models [provider]`, which lists available provider/model identifiers. |
| pi / pi-signed | Run the selected executable as `<executable> --list-models [search]`; Pi's installed `docs/models.md` owns how built-in, extension-registered, and custom provider/model entries reach that list. |
| grok | Run `grok models`, which lists the models available to the current Grok installation and account. |
| kimi | Run `kimi provider list --json`, which lists the current provider and model configuration. |
| cursor | Run `cursor-agent models` (equivalent to `--list-models`), which lists every model id/label pair available to the current account. A model present in that listing can still be rejected at launch on plan-tier grounds (see the Cursor section below); listing presence proves the model exists, not that this account can invoke it. |
| antigravity | Run `agy models`, which lists every model id available to the current account (verified live: includes `gemini-3.6-flash-high\|medium\|low`, `gemini-3.5-flash-high\|medium\|low`, `gemini-3.1-pro-high\|low`, `claude-sonnet-4-6`, `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`). |

For an unfamiliar harness or model namespace, establish support and provider identity from that harness's authoritative CLI help, model listing, or current documentation rather than guessing from a name or prefix.
A listing that reaches the account and does not contain the model is concrete evidence the model is unsupported: block that candidate and quote the result.
A discovery surface you could not reach establishes nothing; report that as uncertainty rather than turning it into a supported or unsupported verdict.

When a requested effort value is outside the harness-specific accepted set, `fm-spawn` records the requested `effort=` in meta but emits no effort flag for that harness.
This preserves launch success instead of passing a known-bad value.

## no-mistakes skill invocation

Send the validation skill using the target harness's skill invocation form.
Natural language is acceptable if uncertain.

- claude: `/<skill>`, for example `/no-mistakes`.
- codex: `$<skill>`, for example `$no-mistakes`; `/<skill>` is claude-only and codex rejects it as "Unrecognized command".
- opencode: no separate verified skill invocation beyond normal slash-command behavior; use natural language if the exact skill command is uncertain.
- pi and pi-signed: no separate verified skill invocation beyond normal command behavior; use natural language if the exact skill command is uncertain.
- grok: `/<skill>`, for example `/no-mistakes` (same form as claude). Verified end to end: grok discovers the user-level `no-mistakes` skill, `/no-mistakes` invokes it, and grok drives a real `no-mistakes axi run`. Like codex's `$`/`/` popups, typing `/<skill>` opens grok's slash-autocomplete, so a too-fast Enter selects the popup entry instead of sending, and for an argument-taking command (like `/no-mistakes`'s optional task-first argument) that first Enter only expands the popup selection into an argument-hint placeholder rather than submitting - a genuine second Enter is required (see the grok section below for the 2026-07-03 incident and fix). `fm_tmux_submit_core`'s retried Enter (used by `fm-send` on the tmux backend) handles this through the structural composer reader; the herdr backend needed a dedicated fix (`fm_backend_herdr_composer_state`, docs/herdr-backend.md) because its prior delta-based verification false-positived on that same popup-close content change.
- kimi: `/<skill>`, for example `/no-mistakes`.
- cursor: `/<skill>`, for example `/no-mistakes`. Verified end to end: cursor-agent discovers the user-level `no-mistakes` skill from `~/.cursor/skills-cursor/` and shows it in the `/` autocomplete with its description, and `/no-mistakes` drives a real `no-mistakes axi run` (observed running `no-mistakes init`, `no-mistakes doctor`, and `gh` calls unattended). Unlike codex/grok, a single Enter submits the highlighted popup entry directly - no popup-swallow hazard was reproduced for a slash command. Plain (non-slash) free text was a different story: see "Submission acknowledgement hazards" below.
- antigravity: NOT verified end to end. `/no-mistakes` typed into a live agy session opens a `/`-autocomplete popup that reports "No matches" - agy does not discover firstmate's user-level `no-mistakes` skill from `~/.claude/skills/` or `~/.agents/skills/` on its own. `agy plugin import claude` (documented as importing skills from a Claude installation) reported "No claude extensions found." when tried against this machine's real `~/.claude/skills/`. Use natural language (e.g. "run the no-mistakes pipeline") until a working discovery or import path is found.

## Submission acknowledgement hazards

A send or key action reporting success is not proof that the intended action happened.
OpenCode can accept and queue an Enter while leaving text visible, Grok can consume Enter in its slash popup without submitting, and Kimi can silently drop a message sent before readiness even though the send returns success.
The shared symptom is a healthy-looking pane with no work in progress, so each adapter must verify the observable postcondition that is specific to its TUI.
Cursor adds a distinct shape of the same hazard, and it is worse than the others here because the shared tmux composer detector cannot see it: a plain free-text follow-up sent to an already-running cursor-agent pane was reproduced needing a SECOND Enter to actually submit (the first left the text still sitting in the composer), while a `/`-prefixed skill invocation submitted cleanly on one. Firstmate cannot currently prove which case a given send hit, because `fm_tmux_composer_state`/`fm_pane_input_pending` classify a live Cursor pane's composer as `unknown` rather than `pending` (the fix below stops the far more dangerous false `empty`, but does not restore a positive `pending` proof) - see the Cursor section for the full evidence and the concrete consequence for `fm-send`.

## claude (VERIFIED; busy-state hooks live-verified 2026-07-28 on Claude Code 2.1.220)

| Fact | Value |
|---|---|
| Busy state | Owned lifecycle hooks: `UserPromptSubmit` opens a turn, `Stop`, `StopFailure`, and `SessionEnd` close it. Claude fires no hook for a manual interrupt, so a firstmate-initiated interrupt must record the clear itself. |
| Exit command | `/exit` |
| Interrupt | single Escape |
| Skill invocation | `/<skill>` (e.g. `/no-mistakes`) |

First launch in a fresh worktree, or first ever on a machine, may show a trust or bypass-permissions confirmation.
After every spawn, peek the pane within about 20 seconds.
If such a dialog is showing, accept it from an active firstmate session using `FM_HOME=<this-firstmate-home> bin/fm-send.sh <window> --key Enter`, or the choice the dialog requires, unless `FM_HOME` is already set to the active firstmate home; verify the brief started processing.

Claude renders a predicted-next-prompt suggestion as dim/faint text inside an otherwise-empty composer after a turn completes.
A plain `tmux capture-pane` cannot tell that ghost text apart from typed text.
Firstmate launches every claude crewmate and secondmate with `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`, scoped to firstmate-launched agents through `bin/fm-spawn.sh`, so it never touches the captain's global config.
The CLI's `--prompt-suggestions` flag is print/SDK-mode only and does not suppress the interactive composer ghost text, verified empirically on v2.1.186.
As defense in depth for any pane that flag cannot reach, including the captain's own firstmate composer that away-mode reads, the shared `fm_composer_strip_ghost` extractor in `bin/fm-composer-lib.sh` removes dim/faint SGR 2 ghost runs before pending-input classification on both ANSI-capable readers (tmux and herdr).
Its broader dark-TRUECOLOR placeholder handling and dark-theme tradeoff are documented in `docs/herdr-backend.md` "Composer and injection safety", with active captures in `docs/verification/runtime-backends.md`.
That styled capture is internal to the boolean detector only.
`fm-peek` and every other human or LLM-facing capture path stays plain `tmux capture-pane` with no escape codes.

**Primary-session guard fact (verified 2026-07-04, Claude Code 2.1.201; preserved 2026-07-08, Claude Code 2.1.204; Stop-owned auto-arm revalidated 2026-07-24, Claude Code 2.1.219).**
This is separate from the per-task crewmate turn-end hook above (that one just `touch`es a marker file in a task's own `.claude/settings.local.json`).
The firstmate PRIMARY's own `.claude/settings.json` registers two Stop hooks: `bin/fm-turnend-guard.sh --claude` and the Stop-owned auto-arm `bin/fm-claude-stop-autoarm.sh` (`asyncRewake: true`, `timeout: 28800`), and exiting the guard with status 2 plus stderr reliably forces the model to continue.
Claude Code's stdin payload to a Stop hook carries a `stop_hook_active` boolean that is `true` when the current stop attempt follows ANY stop-hook-driven continuation, including `asyncRewake` rewakes; the primary guard therefore ignores it in `--claude` mode and uses the cooperative claim/epoch check plus a bounded re-block budget instead, while the codex-mode default still treats it as a one-block loop guard.
A project-level `.claude/settings.json` only takes effect when Claude Code's project root is that exact directory - it does not walk up from a subdirectory looking for one, so firstmate launches the primary from the repo root.
After those settings are loaded, hook command resolution is still cwd-sensitive because Claude Code runs commands through `/bin/sh` against the session's current cwd; keep the tracked commands anchored through `"$CLAUDE_PROJECT_DIR"/bin/...` and see `docs/turnend-guard.md` for the verified Stop-hook details.
Claude Code's primary watcher protocol is Stop-owned: the auto-arm hook fires on every Stop and foregrounds `bin/fm-watch-arm.sh` when the home is eligible and still needs supervision, and its exit-2 `asyncRewake` rewake is the wake; the model drains and handles wakes but never runs a routine re-arm command.

## codex (VERIFIED 2026-06-11, codex-cli 0.139.0)

| Fact | Value |
|---|---|
| Busy state | Unknown until a semantic source is live-verified: the app-server turn lifecycle is unreachable for a pane worker, and project lifecycle hooks did not fire for a firstmate-launched worker. |
| Exit command | `/quit` (slash popup needs about 1 second between text and Enter; `fm-send` handles it) |
| Interrupt | single Escape |
| Skill invocation | `$<skill>` (e.g. `$no-mistakes`); `/<skill>` is claude-only and codex rejects it as "Unrecognized command" |

A `$<skill>` invocation opens a `$`-autocomplete (skill) popup, the same hazard as the `/` slash popup: submitting too fast lets the popup swallow the Enter, so the invocation never lands.
`fm-send` handles it the same way it handles `/` - it gives the popup a longer settle (1.2s) between typing and the first Enter, with the target backend's submit retry as the safety net - but the `$` settle is scoped to `harness=codex`, read from the target metadata for exact task ids or legacy `fm-<id>` labels.
That scope matters because, unlike `/`, a leading `$` commonly starts ordinary text (`$5/month`, `$HOME`), so a universal `$` rule would needlessly slow plain steers to claude/opencode/pi; only a codex target receiving a `$...` message gets the popup-settle.
An explicit `session:window` target has no meta, so its harness is unknown and treated as non-codex (the safe fast-path default).
This is why the validation trigger (`$no-mistakes`) to a codex crew now lands on the first Enter instead of biting the popup.

Directory trust dialog on first run per repo root: "Do you trust the contents of this directory?"
Accept with Enter.
The decision persists for the repo, so later worktrees of the same project skip it.

Resume after exit with `codex resume <session-id>`.
The session id is printed on quit.

**Primary-session guard fact (verified 2026-07-08, codex-cli 0.142.1).**
The firstmate PRIMARY's own `.codex/hooks.json` registers a Stop hook that pipes Codex's Stop payload to `bin/fm-turnend-guard.sh`.
Codex Stop hooks block on exit 2 and expose `stop_hook_active` for the same one-block loop safety Claude uses.
Codex's Stop payload includes `cwd`, but the tracked primary hook does not use it to choose the guard executable.
Verified on 2026-07-08: Codex runs the Stop hook command with process PWD set to the hook-loaded project root, and no `CODEX_PROJECT_DIR`, `CODEX_WORKSPACE_ROOT`, or `CODEX_CWD` root variable is set.
The tracked hook anchors to `pwd -P`, verifies that root is firstmate-shaped and hook-bearing, and then invokes `bin/fm-turnend-guard.sh` with the original payload.
Codex's primary watcher protocol is `bin/fm-watch-checkpoint.sh --seconds "${FM_CODEX_WATCH_CHECKPOINT:-180}"`, not `bin/fm-watch-arm.sh`.
The checkpoint is deliberately foreground and bounded so Codex regains control regularly to process user messages and queued wakes.

## opencode (VERIFIED 2026-06-11, v1.15.7-1.17.6; 1.18.4 busy-queue re-verified 2026-07-20)

| Fact | Value |
|---|---|
| Busy state | The Firstmate-owned plugin's semantic `session.status`: `busy` and `retry` are active, `idle` is inactive, latched to the worker's own session. |
| Exit command | `/exit` |
| Interrupt | double Escape; known flaky while a long shell command runs, so a wedged pane may need `/exit` and relaunch |

No trust dialog.
Opencode can auto-upgrade itself in the background and the running TUI can exit mid-task, observed live from 1.15.7 to 1.17.3.
If a pane shows the exit banner, relaunch with `--continue` to resume the session.
`--prompt` does not auto-submit alongside `--continue`, so send the next instruction via `fm-send` once the TUI is up.

**Busy-queued Enter (opencode 1.18.4, tmux backend fix, herdr known gap).**
While opencode is mid-turn, the composer accepts Enter as a "send when the turn
ends" keystroke but does not clear the typed text from the composer until the
turn actually finishes.
Without a fix, every `fm-send` to a busy opencode pane exits non-zero on a
false "Enter swallowed", and every daemon escalation that lands while the
primary is mid-turn is treated as wedged.
The shared `fm_tmux_submit_enter_core` (`bin/fm-tmux-lib.sh`) now falls back
to `fm_pane_is_busy` once the Enter-retry budget is spent: a busy pane means
the Enter was accepted and queued (reported as `empty` so the caller does not
re-send), while an idle pane keeps `pending` as a genuine swallow. The herdr
adapter observes the same opencode behavior but needs a separate fix; it is
recorded as a known gap in `docs/herdr-backend.md` rather than patched here,
so the tmux adapter does not paper over a herdr-specific shape.
Regression coverage: `tests/fm-tmux-submit-busy.test.sh` covers the four
scenarios (busy + pending -> `empty`, idle + pending -> `pending`, busy +
cleared -> `empty`, idle + cleared -> `empty`).

**Primary-session guard fact (verified 2026-07-08, OpenCode 1.17.6).**
The firstmate PRIMARY's own `.opencode/plugins/fm-primary-turnend-guard.js` listens for `session.idle`.
Throwing from `session.idle` does not block `opencode run`, so the primary adapter treats the event as passive and uses `client.session.promptAsync` to force one follow-up turn when `bin/fm-turnend-guard.sh` returns 2.
The companion `.opencode/plugins/fm-primary-watch-arm.js` owns normal TUI watcher wake supervision and coordinates with the guard plugin before the guard tries a blind-turn follow-up.
The follow-up was verified in the interactive TUI; `opencode run` can exit before displaying a queued follow-up, so the adapter is fail-open in headless mode.

## pi and pi-signed (VERIFIED 2026-07-27)

| Fact | Value |
|---|---|
| Busy state | The Firstmate-owned extension's `agent_start` (busy) and `agent_settled` confirmed by `ctx.isIdle()` (idle), which covers retries, compaction, tool loops, and queued continuations. |
| Exit command | `/quit` |
| Interrupt | single Escape |

Pi has no permission system, so crewmates are always autonomous.
`pi-signed` is the signed wrapper identity verified on version 0.82.0 and exposes the same CLI and TUI behavior as Pi.
Firstmate launches the selected executable name from `PATH`, records `pi-signed` without normalization, and refuses rather than falling back to `pi` when that wrapper is unavailable.
The observed signed process tree is an exact `pi-signed` wrapper parent with the Pi application as its child, while tmux reports the foreground command as the exact `pi-launcher` name for both selected executables.
The installed plain `pi` command also execs that signed launcher, so `FM_PI_HARNESS=pi-signed` is the authoritative selection marker and shared unmarked ancestry remains `pi`.
Firstmate sets `FM_PI_HARNESS` explicitly for both worker launch identities, and a signed primary uses the README launch command to establish the same boundary.
Keep the brief as one positional argument.
Multiple positional args become separate queued messages; `fm-spawn`'s template already does this correctly.

Project trust dialog can appear on the first pi run in any not-yet-trusted directory, observed even on clean worktrees.
Accept with Enter.
The decision persists per path in `~/.pi/agent/trust.json`, so later spawns in the same worktree slot skip it.

`fm-spawn` keeps the turn-end extension in `state/`, outside the worktree, because project-local extension files make the trust gate strictly worse and pollute the project.
The extension must listen for pi's `turn_end` event, not `agent_end`, so the watcher wakes after each completed turn instead of only when the whole agent run exits.
Pi sets `PI_CODING_AGENT=true` for its children; this is its harness-detection env marker.

**Primary-session guard fact (verified 2026-07-09, Pi 0.80.5).**
The firstmate PRIMARY's own `.pi/extensions/fm-primary-turnend-guard.ts` listens for logical-run `agent_settled`, not per-tool-loop `turn_end`, and uses `pi.sendUserMessage(..., { deliverAs: "followUp" })` to force one guarded follow-up when `bin/fm-turnend-guard.sh` returns 2.
Without `deliverAs: "followUp"`, Pi rejects the send while the agent is still processing.
Pi's primary watcher protocol also requires the tracked `.pi/extensions/fm-primary-pi-watch.ts` extension, same trust-once discovery as the turn-end guard.
The model arms through `fm_watch_arm_pi`, never a foreground bash arm; the watcher tool result and clean-exit fallback are owned by `docs/supervision-protocols/pi.md`.
`bin/fm-session-start.sh` reports when the live Pi-family session has not loaded both the turn-end guard and watcher extensions, and points at the selected executable after project trust as the fix, with `-e` as a trust-free fallback.
When a secondmate is launched on Pi or pi-signed, `fm-spawn.sh --secondmate` launches the selected executable with both `-e .pi/extensions/fm-primary-turnend-guard.ts` and `-e .pi/extensions/fm-primary-pi-watch.ts`, both already present in the secondmate home's git worktree.

## grok (VERIFIED 2026-06-29, grok 0.2.73; slash-submit re-verified 2026-07-03 on 0.2.82; reasoning-effort ceiling re-verified 2026-07-13 on 0.2.99; exit paths re-verified 2026-07-19 on grok 0.2.103)

Grok Build TUI (`grok`), a Claude-Code-compatible CLI from xAI.
Launch with a positional prompt: `grok --always-approve "$(cat <brief>)"`.
For Grok's supported reasoning-effort values and omission behavior, see the [launch-profile-axes table](#launch-profile-axes).

| Fact | Value |
|---|---|
| Busy state | The one remaining rendered-tail fallback, isolated to Grok until its structured lifecycle is live-verified: `Ctrl+c:cancel`, the mid-turn cancel hint shown in grok's keybind bar iff a turn is running. The idle bar shows only `Shift+Tab:mode │ Ctrl+.:shortcuts`. ASCII is matched rather than the braille spinner to avoid locale fragility. |
| Exit command | `/exit` typed into the composer exits the TUI cleanly and prints `Resume this session with: grok --resume <session-id>`; `Ctrl+Q` double-press within 1000ms remains a fallback; `Ctrl+D` is the quit key in VS Code family terminals; `Ctrl+C` is the interrupt, not the exit. |
| Interrupt | single `Ctrl+C` (cancels the current turn; the footer shows `Ctrl+c:cancel` mid-turn). `Esc` only moves focus to the scrollback, it does NOT interrupt. |
| Skill invocation | `/<skill>` (e.g. `/no-mistakes`), same as claude. Opens a slash-autocomplete popup, so a too-fast Enter selects the popup entry instead of sending. For an argument-taking command that first Enter does not submit at all - it expands the selection into an argument-hint placeholder in the composer (e.g. `/compact` -> `/compact compaction instructions`, live-verified), leaving real text still sitting there unsubmitted; a genuine second Enter is required. `fm-send`'s retried Enter lands it on BOTH backends, but only because each backend's own submit-verification correctly recognizes that placeholder-filled text as still-pending - see the incident below. |
| Autonomy | `--always-approve` (footer shows `· always-approve`); auto-approves every tool execution, verified to run fully unattended. `--permission-mode bypassPermissions` is the stronger equivalent. |
| Env marker | `GROK_AGENT=1`, set for child/tool processes. grok does NOT set `CLAUDECODE` despite Claude compatibility, so the marker is unambiguous. |
| Resume | `grok --resume <session-id>` (id printed on exit) or `grok -c` / `--continue` (most recent for the cwd); `--fork-session` branches a new session id. |

**Incident (2026-07-03, herdr backend only, grok 0.2.82):** two grok/herdr crewmates were sent `/no-mistakes` via `fm-send`; both left it fully typed but unsubmitted in the composer for minutes (footer still `Enter:send`), and `fm-send` exited 0 with no error.
Reproduced live: the herdr adapter's submit-verification at the time treated ANY pane-content change after Enter as "submitted", and the popup-close-with-placeholder-fill described above IS a visible content change even though nothing was actually sent.
The tmux backend's structural `fm_tmux_composer_state` read sees placeholder-filled text on any content row as still pending, so its retry loop sends the needed second Enter.
The Herdr adapter (`fm_backend_herdr_composer_state`, `bin/backends/herdr.sh`) classifies the composer's own row structurally instead of diffing raw content; see `docs/herdr-backend.md` "Composer and injection safety" for the current boundary and `tests/fm-backend-herdr.test.sh` for regression coverage.

Startup dialog: the "Run Grok Build in a project directory?" project picker appears ONLY when grok is launched from a non-project directory (home, Desktop, Downloads, `/tmp`).
`fm-spawn` launches inside the treehouse worktree (a git repo root), so the picker never appears and grok treats the worktree as a trusted project automatically - no post-launch keystroke is needed.
Pin `[hints] project_picker_disabled = true` in `~/.grok/config.toml` if a non-project launch ever needs to skip it.

**TRUECOLOR placeholder styling: covered (task afk-herdr-false-pending, 2026-07-10).**
A freshly-dismissed, never-typed-into grok composer shows a placeholder ("Type a message...") styled with a dark 24-bit TRUECOLOR foreground, not the SGR-2 dim/faint attribute the ghost stripper originally detected.
The shared ANSI-aware owner `fm_composer_strip_ghost` (`bin/fm-composer-lib.sh`) now drops a dark/muted truecolor foreground (perceived luminance below `FM_COMPOSER_GHOST_LUMA_MAX`, default 128) as well as dim/faint, so the placeholder is stripped and the row reads empty on both ANSI-capable backends (tmux and herdr route through the same owner).
Verified live against grok 0.2.93: real input is the bright `38;2;224;222;244` (luminance ~225, kept), while grok's borders and placeholder/hint text are dark truecolor (`38;2;50;47;70` .. `38;2;110;106;134`, luminance ~51..110, dropped).
This assumes a dark terminal theme, the fleet reality; the SGR-2 signal stays theme-independent.
Regression coverage: `tests/fm-composer-ghost.test.sh` (`test_strip_ghost_drops_dark_truecolor_ghost`, `test_dark_truecolor_ghost_only_composer_is_not_pending`) and `tests/fm-backend-herdr.test.sh` (`test_composer_state_grok_dark_truecolor_placeholder_is_empty`, `test_composer_state_grok_bright_truecolor_real_text_is_pending`).

**Tmux bottom-border cursor quirk (fixed):**
In a pristine placeholder-only composer, tmux's `#{cursor_y}` can point at the box's bottom border instead of its text row.
The shared tmux reader now locates the complete box structurally and classifies every content row, so the cursor may sit on a content row or the bottom border without changing the result.
The same structural read covers multi-row composers without fixed cursor offsets, while Herdr retains its own structural composer-row scan.

Turn-end hook: grok fires a `Stop` hook at every turn boundary, giving firstmate a precise per-turn wake instead of only stale-pane detection.
grok loads PROJECT hooks (`<worktree>/.grok/hooks/`, `<worktree>/.claude/settings.local.json`) only after the folder is granted hook-trust in `~/.grok/trusted_folders.toml`, which is not automatic and which firstmate will not establish by editing grok's own managed trust store.
GLOBAL hooks in `~/.grok/hooks/` are always trusted and load on first launch.
So `fm-spawn` installs ONE firstmate-owned global hook, `~/.grok/hooks/fm-turn-end.json`, plus the companion `~/.grok/hooks/fm-turn-end.sh`, guarded as a no-op for every non-firstmate grok session.
Its `Stop` command fires only when the current workspace holds a `.fm-grok-turnend` token pointer that matches the firstmate-owned hook registry under `~/.grok/hooks/fm-turn-end.d/`.
`fm-spawn` writes that per-task pointer (`<worktree>/.fm-grok-turnend`, gitignored via git info/exclude like the other harnesses' worktree hook files) and a matching registry entry naming this task's `state/<id>.turn-ended`.
The hook reads `$GROK_WORKSPACE_ROOT`, which is always set for hooks and equals the worktree.
This keeps the hook outside the worktree, needs no trust grant, and writes only firstmate-owned files.
`fm-teardown` removes the worktree pointer before returning a pooled worktree.
Secondmate spawns skip the pointer (idle panes are healthy, no stale-pane detection for them).

**Primary-session guard fact (verified 2026-07-28, Grok 0.2.112 and 0.2.73).**
The firstmate PRIMARY's own `.grok/hooks/fm-primary-turnend-guard.json` invokes `bin/fm-turnend-guard-grok.sh`.
Grok 0.2.112 exposes native same-process Stop continuation in its running payload, while the genuine pre-native 0.2.73 payload omits that capability and still needs one guarded `grok --resume`.
The exact adaptive and malformed-input contract is owned by `docs/turnend-guard.md`.
The tracked Claude Stop hooks skip themselves under `GROK_AGENT`, because Grok also loads Claude-compatible project settings and otherwise creates a second blocking path.
Project-local Grok hooks require folder trust, verified with launch-time `--trust`; if the primary firstmate checkout is not trusted for Grok hooks, this primary guard fails open and `fm-guard.sh` remains the next-command alarm.
Grok's primary watcher protocol remains background-notify around `bin/fm-watch-arm.sh`; native Stop continuation does not provide Pi-like extension ownership.

## kimi (VERIFIED 2026-07-25, kimi 0.29.1)

Kimi Code CLI launches from the absolute path resolved from `PATH`, falling back to the executable `$HOME/.kimi-code/bin/kimi`.

| Fact | Value |
|---|---|
| Binary | Executable `kimi` from `PATH`, then executable `$HOME/.kimi-code/bin/kimi`; spawning refuses if neither exists. |
| Launch | Bare interactive TUI with `--auto`, followed by readiness-gated pointer delivery; positional prompts are rejected. |
| Models | `kimi-code/kimi-for-coding` (default), `kimi-code/kimi-for-coding-highspeed`, `kimi-code/k3`, and `kimi-code/k3-256k`. |
| Busy state | Standalone Kimi is unknown until a semantic source is live-verified; prefer Wire's `prompt` request lifetime, then documented hooks including `Interrupt`. Kimi behind Pi uses Pi's lifecycle. Its moon-phase spinner is not a state source. |
| Exit command | `/exit` |
| Interrupt | Single Escape, which prints `Interrupted by user`. |
| Skill invocation | `/<skill>`, for example `/no-mistakes`; firstmate skills are discovered. |
| Autonomy | `--auto`; `-y` and `--yolo` are weaker and are not used. |
| Trust dialog | None on a clean first launch in a fresh pooled worktree. |
| Slash submission | One Enter submits, with no popup swallow or settle hazard. |
| Environment marker | None; detection relies on process ancestry command name `kimi`. |
| Composer | Bordered box with a bare `>` prompt glyph and no observed ghost or placeholder text. |
| Effort | No reasoning-effort flag exists, so requested effort is recorded in task metadata but omitted from launch. |

`fm-spawn.sh` launches Kimi bare, waits for the composer box or `Welcome to Kimi Code!`, sends only `Read the brief at <absolute-path> and follow it exactly.`, and requires a cleared composer plus either the echoed `✨` submission or nonzero context before accepting delivery.
This launch-then-send shape is mandatory because Kimi rejects a positional brief as an unknown command.
Sending before readiness was reproduced as a silent drop with a zero exit status, an empty composer, `context: 0%`, no echoed user message, and a healthy-looking idle pane.
The brief path must be absolute because the brief lives outside the task worktree, and Kimi reads it there without `--add-dir`.

Observed live spinner captures included optional leading whitespace, a moon-phase glyph, whitespace around `·`, and rotating tip text, with the same shape observed during tool execution.
Because every captured spinner row had whitespace on both sides of `·`, the matcher requires that whitespace, deliberately does not match the never-observed zero-whitespace form, and does not require trailing tip text.
The startup input-readiness window is the established cause of Kimi's first-Enter delivery defect, while the banner is not the cause.
An early Enter can expand Kimi's composer to multiple content rows, leaving the pointer text on the first row and the cursor on an empty later row, which is the same single-cursor-row reading defect exposed by Grok's bottom-border cursor quirk.
The shared tmux reader now locates the complete bordered composer and treats real text on any content row as positive evidence that submission is still pending.
No rendering signal is trustworthy for proving that Kimi will accept input during this window, so delivery retries Enter through the shared submit core and retains the existing postcondition verification rather than relaxing readiness or delivery checks.
Kimi's footer tip rotates independently and can display `ctrl+c: cancel` while completely idle, which is one reason no Kimi rendered signature is a state source.
The idle status bar can contain lowercase `thinking`, which is the model's effort label rather than a busy signal.
The delivery-only spinner match covers the full moon-phase glyph set rather than one frame, but it remains locale- and emoji-font-sensitive because Kimi exposes no stable ASCII busy token.

[`docs/turnend-guard.md`](../../../docs/turnend-guard.md) owns Kimi's verified global hook surface and captain-approved crew wake integration.
`fm-spawn.sh` installs one marker-delimited Firstmate entry in `$HOME/.kimi-code/config.toml`, one silent always-zero hook script, and one private token registry under `$HOME/.kimi-code/fm-turn-end.d/`.
Each Kimi crew worktree receives a gitignored `.fm-kimi-turnend` token pointer, and the global hook touches that task's `state/<id>.turn-ended` only when the Stop payload's `cwd`, pointer, and registry entry all agree.
A guarded silent hook cannot be verified from absence of effect, so prove invocation with an unguarded probe before concluding that the hook did not fire.
The guarded turn-end signal remains a wake notification; standalone Kimi has no busy-state source until one is live-verified.

## cursor (VERIFIED 2026-08-02, cursor-agent 2026.07.23-e383d2b)

Cursor CLI (`cursor-agent`), Cursor's own agent runtime, worker-only (see the primary-session exclusion below).
Launch with a positional prompt: `cursor-agent --force --trust --model <model> "$(cat <brief>)"`.
Never pass `-w`/`--worktree`: it creates a second, untracked worktree under `~/.cursor/worktrees/<reponame>/<name>` instead of using the one firstmate allocated, breaking the worktree-isolation assertion every ship brief depends on.

| Fact | Value |
|---|---|
| Launch | Bare interactive TUI with a positional prompt, `--force --trust --model <model>`; the prompt auto-runs once trust and autonomy are granted - verified the same shape as claude/grok, NOT Kimi's launch-then-send (a multi-line prompt was also verified to run correctly). |
| Busy state | Unknown until a semantic source is live-verified: `--help`, every subcommand (`mcp`, `plugin`, `create-chat`, `ls`, `resume`), and `~/.cursor/` config expose no lifecycle-hook or event-stream mechanism; `--output-format stream-json` is print/`-p`-only (headless one-shot), not available to the supervised interactive TUI a pane worker runs. A rendered busy footer (`ctrl+c to stop`) was observed but is deliberately not wired as a fallback - the busy-state redesign scopes the one surviving rendered-tail arm to `harness=grok` only (see "Submission acknowledgement hazards" above and `bin/fm-busy-lib.sh`). |
| Exit command | `/exit` (`/quit` is a documented alias, same "Exit" label in the `/` popup); a single Enter submits it directly, no popup-swallow. Printed `To resume this session: agent --resume=<uuid>` and returned to the shell cleanly. |
| Interrupt | single Escape - verified it stops a running turn ("Cancelled" shown against the running command), NOT a scrollback-only move like grok's Escape. `Ctrl+C` also interrupts the current turn, but a second `Ctrl+C` in quick succession shows `Press Ctrl+C again to exit` and will exit the whole TUI (unconfirmed second press was observed to time out safely rather than exit) - never send a rapid double interrupt to a Cursor pane the way a double-Escape recovery playbook might for another harness. |
| Skill invocation | `/<skill>` (e.g. `/no-mistakes`); see the dedicated list entry above for the discovery and popup-submit evidence. |
| Autonomy | `-f`/`--force` (alias `--yolo`); verified to run fully unattended - a `/no-mistakes` invocation ran `no-mistakes init`, `no-mistakes doctor`, and `gh`/`git` shell commands with no visible approval prompt. `--auto-review` (a weaker server-classifier mode) is not used. |
| Trust dialog | "Workspace Trust Required" appears on first launch in ANY not-yet-trusted directory (`[a] Trust this workspace` / `[q] Quit`, arrow-navigable, `a` accepts) - reproduced even with `--force` alone. `--trust` fully suppresses it, verified in a directory that had never been opened by cursor-agent before; firstmate bakes `--trust` into the launch template rather than handling the dialog post-launch, because every spawn is into a fresh, single-use treehouse worktree firstmate already owns - auto-trusting it is the direct equivalent of claude's `--dangerously-skip-permissions`, not a broadened grant. Trust persists per path (confirmed: a `--resume` relaunch in the same directory showed no dialog). |
| Resume | `cursor-agent --resume=<chat-id>` (id printed on `/exit`); verified to reload the prior conversation and land on the same idle composer with no trust dialog. `--continue` (most recent for the cwd) and `create-chat`/`ls`/`resume` subcommands exist but were not separately exercised. |
| Env marker | `CURSOR_AGENT=1`, set for child/tool processes only (verified: present in a shell command's environment, absent from the top-level `cursor-agent` process's own environment) - the same child-process-marker shape as `GROK_AGENT`, not a top-level marker. `CURSOR_INVOKED_AS=cursor-agent` is also set but was not adopted as the primary marker since it was observed only on the top-level process, the opposite scope firstmate's own detection script (`fm-harness.sh`) runs from. |
| Process comm | `ps -o comm=`/`/proc/<pid>/comm` for the cursor-agent process itself reports the literal string `MainThread` (verified: a Node runtime-thread-naming quirk, not `cursor-agent` or `node`) - do not pattern-match `comm` against `*cursor*`. tmux's own `#{pane_current_command}` is unaffected and correctly reports `cursor-agent` (verified), which is what `bin/backends/tmux.sh`'s agent-liveness classifier and `fm-harness.sh`'s ancestry fallback (`MainThread` + `cursor-agent` in `ps args`) both key on instead. |
| Effort | No reasoning-effort flag exists; effort is encoded IN the `--model` id itself (e.g. `claude-opus-5-thinking-high`, `cursor-grok-4.5-medium`). `--help` documents a bracket-parameter override shape (`'claude-opus-4-8[context=1m,effort=high,fast=false]'`) that was tested directly against the installed CLI and rejected outright as an unrecognized model id ("Cannot use this model: claude-opus-4-8[effort=high]. Available models: ..."), so it is not a working alternate axis on this version. Firstmate resolves the intended effort into the chosen `--model` value at intake; a separately requested `--effort` is recorded in task metadata (`fm-spawn.sh` already does this for every harness) and MUST NOT be assumed honored - there is no flag that reaches it. |
| Model discovery | `cursor-agent models` (equivalent to `--list-models`); see the model-discovery table above for the plan-tier caveat. |

**Cursor is VERIFIED-EXCEPT-MODEL-TIER (captain decision, 2026-08-02): dispatch must stay pinned to `auto` until a Pro-tier named-model turn is confirmed.**
The authenticated account observed throughout this verification (`cursor-agent status`/`about`) is `t.karlmarx@gmail.com` on Cursor's Free tier - not the captain's paid Cursor Pro subscription the task that added this adapter was framed around, and not the captain's own email.
Every named `--model` invocation on this account was rejected with `ActionRequiredError: Named models unavailable Free plans can only use Auto. Switch to Auto or upgrade plans to continue.`; only `--model auto` (or omitting `--model`) produced a real response.
This is a plan-tier rejection from the backend, not a flag-parsing error - the CLI accepted the `--model` flag and its exact value syntactically every time, including for names later confirmed present in `cursor-agent models`' own listing - so launch mechanics, trust, autonomy, exit, interrupt, and skill invocation are verified independent of this gap.
What is NOT verified end to end, and the captain has explicitly decided NOT to block this adapter on: that a real named/effort-bearing model (the entire point of folding effort into the model id) actually completes a turn on this installed CLI and account.
**Standing operating rule until that confirmation lands:** every `cursor` crewmate/scout dispatch - static `config/crew-harness` and every `config/crew-dispatch.json` profile - MUST use `--model auto` (or omit `--model`) and MUST NOT select a named model or a specific effort level for `cursor`. (`config/secondmate-harness` is out of scope because a `cursor` secondmate is refused outright; see below.)
Once a real named-model turn is confirmed end to end on an account with actual Pro access (record the version, account tier, exact model id, and observed output here, in this same style), this rule and its captain-decision framing should be replaced with an ordinary verified fact, not layered under it.

**Composer/steering hazard (confirmed 2026-08-02) - read before trusting `fm-send` delivery to a live Cursor pane.**
Cursor's composer is a full-width, borderless box: a solid rule of `▄` (U+2584) above and `▀` (U+2580) below, no side border characters, styled with SGR-2 dim text and a single reverse-video (SGR 7) character standing in for a synthetic blinking cursor inside otherwise-dim placeholder text (`→ Add a follow-up` once a turn has run, `→ Plan, search, build anything` before the first turn).
None of that alone would need adapter-specific work - except that the REAL terminal cursor cursor-agent leaves behind (`tmux display-message '#{cursor_y}'`) does not track the visible composer row at all: it was observed pinned to the same blank scrollback row regardless of whether the composer was genuinely empty or held real unsubmitted typed text (`hello world test 123`, typed and left unsent, was still on-screen while `cursor_y` reported the identical row as the idle case).
Reproduced concretely: before the fix below, `fm_tmux_composer_state` on a live Cursor pane returned `empty` in BOTH cases, because Cursor's borderless rule isn't a recognized box family, so the shared detector fell through to reading whatever blank row the real cursor happened to be parked on and reported it proven-empty.
That is the same class of failure as the Kimi silent-drop incident above, reproduced by a new adapter: `fm-send`'s submit-verification treats `empty` as proof an Enter landed, so a steer that never actually submitted would have returned success.
Free-text follow-ups typed into an already-running Cursor pane were also observed needing a second Enter to submit (the first left the text sitting in the composer unsubmitted), while a `/`-prefixed skill invocation submitted cleanly on one Enter in the same session - see "Submission acknowledgement hazards" above.

The fix (`bin/fm-tmux-lib.sh`'s `fm_tmux_find_composer_box`) is structural and additive only: while scanning the pane, it separately tracks the last complete `▄`-only-row/`▀`-only-row pair (no existing verified harness draws a solid half-block rule, so this is a no-op for claude/codex/opencode/pi/grok/kimi, confirmed by the full existing composer/tmux test suite passing unchanged) and forces the box-scan's `unsafe`/`unknown` path when the real cursor position sits outside that pair.
This closes the dangerous false `empty` - the fixed detector was verified to return `unknown` for both the idle and the real-pending-text fixture - but it does NOT restore a positive `pending` proof: Cursor's composer state is `unknown` in both the genuinely-idle and genuinely-pending case.
Consequence for supervision: `fm_pane_input_pending` treats anything not proven `empty` as pending and defers (safe - the away-mode injector will not treat a Cursor pane as a confirmed injection target).
`fm-send` does NOT retry on a Cursor pane, and the grok/codex second-Enter mitigation above does not transfer here: `fm_tmux_submit_enter_core` only continues its retry loop on `pending`/`pending-unproven`, so the `unknown` this detector now returns for every live Cursor pane hits the loop's default arm and returns after the FIRST Enter, leaving the busy-queued-Enter exception below the loop unreachable too.
Combined with the observed second-Enter requirement for free-text follow-ups, a free-text steer to a live Cursor pane must be ASSUMED UNSUBMITTED - the text is most likely still sitting in the composer - until visually confirmed; `fm-send` reports that honestly as a non-zero "delivery unconfirmed" exit rather than a false success, which is the safe direction but not a mitigation.
This is a detector gap, not a retry-semantics bug: the retry arm is shared by every harness, so widening it to `unknown` is deliberately NOT the fix - the fix is the bespoke Cursor composer reader below.
Treat a `fm-send` return code to a live Cursor pane as advisory, not proof, until a bespoke Cursor composer reader (structural, independent of `cursor_y`, in the shape of Kimi's own bespoke `kimi_capture_has_empty_composer` rather than the shared cy-based detector) is built and verified - out of scope for this change, which stops at making the shared detector fail safe instead of fail dangerously.
Regression coverage: `tests/fm-composer-ghost.test.sh` (both half-block fixtures plus the no-crossover case for bordered harnesses); `tests/fm-cursor-harness.test.sh` covers harness identity (detection plus the session-lock ancestry/liveness path), not the composer.

**Cursor is a crewmate/scout runtime only (firstmate decision, 2026-08-02) - `--secondmate` is refused outright.**
A secondmate runs its own primary Firstmate session in its own home, and cursor has none of the four primary-session integrations that session needs: no turn-end guard, no PreToolUse seatbelt, no session-start nudge, and no primary watcher supervision.
The task that added this adapter permitted secondmate support only "if it falls out for free," and it did not: the launch template being kind-agnostic (identical command for ship/scout/secondmate, matching grok's shape, needing no per-kind extension files the way pi/codex do) made the *launch* look free, but a secondmate's own primary session still needs the four integrations above, and none of them exist for cursor.
`bin/fm-spawn.sh` refuses a `--secondmate` spawn with `harness=cursor` outright through every resolution path (`config/secondmate-harness`, an explicit `--harness cursor` override, and the bare positional adapter name), before any endpoint or worktree is created, with a diagnostic naming the reason.
`bin/fm-session-lock-lib.sh`'s `FM_HARNESS_RE` deliberately has no cursor alternative, so a cursor-agent process (comm `MainThread`) can never resolve as a session-lock holder.
An earlier fix round took the other path - adding a dedicated `MainThread`-identity to `fm-session-lock-lib.sh` so lock acquisition would succeed - which was reverted as the wrong fix: it would have let a cursor secondmate look supported while running with no supervision at all, worse than refusing it.
Regression coverage: `tests/fm-secondmate-harness.test.sh`'s `test_spawn_cursor_secondmate_refused` pins the spawn-time refusal (every resolution path); `tests/fm-cursor-harness.test.sh`'s `test_session_lock_has_no_cursor_identity` pins the session-lock absence.
Crewmate/scout dispatch, and everything else recorded in this section, is unaffected.

**Primary-session scope.** This verification covers cursor-agent as a firstmate-launched WORKER only.
Turn-end guard, PreToolUse seatbelt, session-start nudge, and primary watcher supervision integrations for a Cursor PRIMARY session are out of scope and not attempted; `README.md`'s primary-harness requirements list is intentionally unchanged.

**Adjacent adapter note (not built here).** `cursor-agent --acp` was not tested, but Cursor's own CLI ecosystem and `no-mistakes doctor`'s `cursor` entry both reference the Agent Client Protocol, and GitHub Copilot CLI exposes `copilot --acp` on this machine (`copilot` 1.0.77, separately installed).
There may be a shared ACP-based path worth investigating for a future Copilot adapter; this task does not explore or build it.

## antigravity (VERIFIED 2026-08-02, agy 1.1.9)

Antigravity CLI (`agy`), Google's own agent runtime for the Antigravity product, worker-only (see the primary-session exclusion below).
Launch with a positional prompt: `agy --dangerously-skip-permissions --new-project --model <model> -i "$(cat <brief>)"`.

**The agent is NOT `language_server_linux_x64`.** The Antigravity editor bundles `/usr/share/antigravity/resources/app/extensions/antigravity/bin/language_server_linux_x64`, and its `--help` advertises a full `-cli`/`-print`/`-agent_mode`/`-dangerously-skip-permissions` surface that looks like exactly the right adapter target.
It is not: every invocation shape tried against the installed build (bare `-cli`, `-print="<prompt>"`, `-agent_mode`) hung with zero stdout/stderr for 120+ seconds while its own internal log recorded a real `401 UNAUTHENTICATED` from the backend, across more than ten variations - default and custom `-gemini_dir`/`-app_data_dir`, a byte-for-byte copy of the real authenticated app-data directory, a positional workspace argument, and an explicitly captain-trusted workspace path.
None of that was the actual cause: string search against the installed binary (`grep -ac "Creating CLI server backend" language_server_linux_x64`, `keyringAuth: loaded token`, `ChainedAuth`) returns zero for all three - the installed `/usr/share/antigravity` build (134MB, dated 2026-04-16) contains none of the code paths that log those lines, while `agy` (193MB, downloaded 2026-08-02, at `~/.local/bin/agy`) contains all of them.
The installed language-server binary's standalone `-cli` mode is simply not the same, working product as `agy`; do not retest it as an adapter candidate without first confirming a newer build actually contains that code (the string-search commands above are the fast disqualifying check).

| Fact | Value |
|---|---|
| Launch | Bare interactive TUI with a positional prompt via `-i`, `--dangerously-skip-permissions --new-project --model <model>`; the prompt auto-runs once autonomy is granted - verified the same shape as claude/grok, NOT Kimi's launch-then-send (a multi-line prompt was also verified to run correctly as one message). |
| Busy state | Unknown until a semantic source is live-verified: agy's own changelog documents real `Stop` and `PostToolUse` hooks (the same lifecycle-hook shape Claude Code uses), but locating and wiring agy's hooks-config equivalent is a task-sized project of its own and was not attempted here - see `fm_busy_antigravity_semantic_source` (`bin/fm-busy-lib.sh`). A rendered busy footer (`esc to cancel` mid-turn vs `? for shortcuts` idle) was observed but is deliberately not wired as a fallback - the busy-state redesign scopes the one surviving rendered-tail arm to `harness=grok` only. |
| Exit command | `/exit`; a single Enter submits it directly, no popup-swallow. Printed `Resume with -c (or command below): agy --conversation=<uuid>` and returned to the shell cleanly. |
| Interrupt | single Escape - verified it stops a running turn (`⎿  Interrupted · What should Antigravity CLI do instead?` shown against a running shell command), not a scrollback-only move. |
| Skill invocation | `/<skill>` opens agy's own `/` autocomplete, but `/no-mistakes` was NOT discovered (see the skill-invocation list above) - not verified end to end. |
| Autonomy | `--dangerously-skip-permissions`; verified to run fully unattended. Verified WITHOUT it: a tool call requiring approval is auto-denied fast with a clear message on stderr (`jetski: no output produced - a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied. ... re-run with --dangerously-skip-permissions`) and exit code 2 - a clean refusal, not a hang. Verified WITH it: the identical tool call (a real shell command) completed and its output was observed on disk. |
| Trust dialog | None observed in any of 8+ never-before-seen directories with `--dangerously-skip-permissions` set, including the treehouse pool worktree path and a plain `/tmp` scratch directory - unlike cursor-agent, no separate `--trust` flag exists or was needed. `~/.gemini/antigravity-cli/settings.json`'s `trustedWorkspaces` list was read but never observed to change across any of these launches. |
| Resume | `agy --conversation=<chat-id>` (id printed on `/exit`) or `-c`/`--continue` (most recent for the cwd, per `--help`); the exact `--conversation=` form was verified via the printed resume line, `-c`/`--continue` were not separately exercised. |
| Env marker | `ANTIGRAVITY_AGENT=1`, set for child/tool processes only (verified: present in a shell command's environment via `agy` running `env \| grep -i antigrav`) - the same child-process-marker shape as `GROK_AGENT`/`CURSOR_AGENT`, not a top-level marker. |
| Process comm | `ps -o comm=`/`/proc/<pid>/comm` and tmux's `#{pane_current_command}` both report the literal string `agy` for the top-level process (verified) - no MainThread-style quirk at the top level, unlike cursor-agent. `agy` does spawn child helper processes with comm `MainThread` (observed during teardown's lingering-process sweep, matching the same Node-runtime-thread-naming quirk cursor-agent's own top-level process has), but that never reaches `bin/backends/tmux.sh`'s foreground-only liveness probe. |
| Effort | A real `--effort low\|medium\|high` flag exists but is unsafe to combine with `--model` - see the launch-profile-axes table above and the flag-ordering note below. |
| Model discovery | `agy models`; see the model-discovery table above. |
| Account observed | `info.rudratic@gmail.com (Google AI Pro)` - a real paid tier, confirmed live from the TUI's own startup banner. `--model claude-sonnet-4-6` and `--model gemini-3.6-flash-high` each produced a genuine model response (including a real extended-thinking trace for Claude Sonnet 4.6), not a plan-tier rejection - antigravity does not carry Cursor's "verified-except-model-tier" caveat. |

**`--new-project` is required, or tool execution silently targets the wrong directory (confirmed 2026-08-02).**
Without `--new-project`, a shell-command tool call from `agy --dangerously-skip-permissions -i "..."` completed successfully and reported success, but the file it wrote landed in a shared `~/.gemini/antigravity-cli/scratch/` directory - not the actual launch cwd, and not any path visible in the reported `workspaceDirs` for that session.
With `--new-project` added (and every other flag held identical), the identical command wrote to the actual launch cwd, verified by `pwd` output inside the tool call landing in the file.
This is a silent-wrong-directory failure, not a silent-drop: the tool call succeeds, reports success, and even names a plausible-looking path in its own confirmation text, but a crewmate launched without `--new-project` would silently edit nothing in its assigned worktree while reporting done.
`fm-spawn.sh`'s launch template always includes `--new-project`.

**`--model` must precede `-i`, and `--effort` must never be passed at all (confirmed 2026-08-02).**
A `--model claude-sonnet-4-6` flag placed AFTER the `-i "<prompt>"` positional argument was silently ignored - the session ran on agy's own last-used default model (Gemini) instead, confirmed by asking the live session to name its own model.
The identical flag placed BEFORE `-i` was honored, confirmed the same way, including a real extended-thinking response from Claude Sonnet 4.6.
`fm-spawn.sh`'s launch template places `__MODELFLAG__` before `-i` for this reason.
Separately, `--effort` (which DOES exist as a real flag, unlike cursor) was verified to corrupt `--model` resolution even when correctly ordered: `--model claude-sonnet-4-6 --effort medium` silently fell back to the default Gemini model with no error, and `--model gemini-3.5-flash-low --effort low` silently ran as `Gemini 3.5 Flash (Medium)` - `--effort` overrode the model's own baked-in effort suffix to an unrequested value rather than composing with it.
`fm-spawn.sh` never emits `--effort` for antigravity; the intended effort must be folded into the chosen `--model` value at intake instead (see the launch-profile-axes table).

**Composer shape: a bare, non-bordered `>` prompt glyph - no code change needed (confirmed 2026-08-02).**
agy's composer is a single content row (`> <text>`, styled `38;5;69`) between two full-width plain horizontal rules (`─`, not Cursor's half-block `▄▀` rule and not any bordered box family); the real terminal cursor (`#{cursor_y}`) correctly tracks that exact row in both the idle and pending-text cases, verified with a captured fixture in both states.
Because the row is a bare `>` with no enclosing box, `bin/fm-tmux-lib.sh`'s existing shared classifier already handles it exactly as it handles a possible dead shell prompt: `fm_composer_classify_content`'s pre-existing rule for a bare `>`/`$`/`%`/`#` glyph outside a bordered box returns `unknown` (never `empty`) precisely because a bare `>` cannot be distinguished from a genuine dead shell without further structure, and real unsubmitted text on that row returns `pending` as normal.
This was verified directly against the unmodified `fm_tmux_composer_state` using real captured idle and pending-text fixtures from a live agy session (idle -> `unknown`, pending -> `pending`), so - unlike Cursor's half-block rule, which needed a real structural fix - antigravity's composer shape needed no change to `bin/fm-tmux-lib.sh` or `bin/fm-composer-lib.sh`.
The practical consequence matches Cursor's: `fm_pane_input_pending` treats the never-proven-empty idle composer as pending and defers rather than injecting, and `fm-send`'s submit-retry core falls through its Enter-retry budget rather than reaching a positive `empty` confirmation.

**Full end-to-end spawn verified (2026-08-02).**
A real task was spawned through `bin/fm-spawn.sh`'s raw-launch-command escape hatch against a scratch git repository, over the tmux backend (`--backend tmux`), using the exact launch template above.
The worktree was allocated, the encoded launch brief was delivered and rendered correctly (including the `FIRSTMATE_OP:` marker), the session ran unattended on the requested model, replied with the exact requested string, and returned to an idle composer; `tmux display-message -p '#{pane_current_command}'` read `agy` throughout.
`bin/fm-teardown.sh` cleanly killed the lingering `agy`/`MainThread`/shell process tree and returned the worktree to the pool.
Only a crewmate (ship) launch was spawned and observed end to end; the secondmate path was not independently exercised, but the launch template is kind-agnostic (identical command for ship/scout/secondmate, matching grok's and cursor's shape) and agy needs no per-kind extension files, so `--secondmate` dispatch falls out of the same code path with no separate wiring.

**Primary-session scope.** This verification covers agy as a firstmate-launched WORKER only.
Turn-end guard, PreToolUse seatbelt, and session-start nudge integrations for an Antigravity PRIMARY session are out of scope and not attempted; `README.md`'s primary-harness requirements list is intentionally unchanged.

**Follow-up not built here.** agy's real `Stop`/`PostToolUse` hook system (see "Busy state" above) is a credible path to a genuine semantic busy source, matching Claude's own hook-based wiring, but locating agy's hooks-config file, its exact payload shape, and verifying it fires for a firstmate-launched worker is unattempted and left as a follow-up task.

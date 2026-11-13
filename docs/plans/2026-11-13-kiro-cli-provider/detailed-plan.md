# Detailed plan: Kiro CLI as a third agent CLI (milestone 1)

base_commit: 7912f81
branch: chat-and-astryx
plan folder: docs/plans/2026-11-13-kiro-cli-provider/ (workers must not touch it)
Read first: big-picture.md (goals, non-goals, constraints, acceptance) and research.md (code map and Kiro facts).

## Shared context (pass to every task)

- Repo `/Users/dung.nguyen/Documents/Projects/agent-hub`. Rust daemon and `echoctl` CLI in `crates/hub/` (package `echoctl`); Swift app in `app/`. Read `CLAUDE.md` and `docs/decisions/README.md` before editing; read `docs/decisions/features/0036-*.md`, `0037-*.md` and `0068-*.md`, and the `docs/bugs/` files whose Where line names an area you change.
- Kiro is the third `Cli` arm, built on Codex's pattern (hook reports the session id, resume by id, screen read for states). 0068 is the decision; if the spike (T01) shows 0068 cannot hold, stop and report `blocked` with the evidence; do not rewrite 0068 (committed decisions are never edited; a superseding file is the planner's call).
- Tests: `~/.cargo/bin/cargo test -p echoctl`, `~/.cargo/bin/cargo fmt --check`, `make -C app test`. Never use the human's daemon, repos or tmux sessions: `HUB_STATE=/tmp/hubk` (short path), a throwaway repo under `/tmp`, `HUB_TEST_AGENT=crates/hub/tests/fake-agent.sh` for daemon tests. A real `kiro-cli` run spends the human's credits: use `--model claude-haiku-5.5` and short prompts.
- `~/.kiro` belongs to the human. Add only `~/.kiro/agents/echo-*.md` files (the spike: `echo-spike-*.md`, deleted afterwards). Never modify or delete anything else there.
- One commit per task on the current branch, message `Daemon: ...`, `Echo: ...` or `Docs: ...`, no attribution, no em dashes. Never push, amend or rebase. Leave the tree clean.
- The terminal Echo gives an agent is 45 rows by 160 columns; the spike must capture screens at that size.

## Tasks

### T01 Spike: what Kiro's TUI, hooks and shell tool really do
- id: T01
- agent: naruto
- depends_on: none
- files: `docs/research/kiro-cli-spike.md` (new), `crates/hub/tests/fixtures/kiro/*.txt` (new screen captures), temporary `~/.kiro/agents/echo-spike-*.md` (deleted at the end), scratch under `/tmp/kirospike*`
- goal: answer Q1 to Q13 below with evidence from real runs of `kiro-cli` 3.2.1, and write them to `docs/research/kiro-cli-spike.md`. The file starts with a line `Verdict: GO` or `Verdict: NO-GO: <why>`, then one section `### Qn` per question, each with `PASS`, `FAIL` or `NOTE`, the command or keys used, and the observed output. NO-GO only when Q2 fails with no workaround (no way to learn the session id) or Q3 and Q6 both fail (no way to see states and prompts); everything else is a finding for the later tasks.
- method: use tmux, never the human's sessions. `tmux new-session -d -s kirospike -x 160 -y 45 -c /tmp/kirospike-repo 'kiro-cli chat --v3 ...'`, `tmux send-keys -t kirospike ...`, `tmux capture-pane -p -t kirospike`, `tmux kill-session -t kirospike` at the end. `/tmp/kirospike-repo` is a throwaway `git init` repo. Hooks in the spike agent file run `/tmp/kirospike/hook.sh`, a stub that writes its stdin to `/tmp/kirospike/hook-<event>.json` and `env | grep -E '^(HUB_|KIRO|ECHO_)'` to `/tmp/kirospike/hook-env.txt`. Test with `HUB_WORKER=w99 HUB_AGENT=7` exported in the tmux command to see whether hooks inherit them. Use `--model claude-haiku-5.5`.
- questions:
  - Q1. Is a Markdown agent file `~/.kiro/agents/echo-spike-a.md` (front matter `name`, `description`, `model`, `tools`, `permissions.rules`, `hooks`; the body is the prompt) picked by `--agent echo-spike-a`, and does the body reach the model (ask it to repeat a codeword from the body)? Does `--agent` need the name or the file path? Does a generated file need to be in `~/.kiro/agents` or does `<cwd>/.kiro/agents` work too?
  - Q2. Does a `SessionStart` hook in the agent file fire in an interactive V3 session at start (and again on resume)? Record the stdin JSON exactly (`hook_event_name` value, `session_id` format, `cwd`) and whether `HUB_WORKER`/`HUB_AGENT` reach the hook's environment. If not inherited, can the hook command carry them (for example `HUB_WORKER=w99 echoctl notify` in the command string)?
  - Q3. Does a `Stop` hook fire at the end of every turn, with what stdin JSON? Does it fire when the turn ended by `Esc` interrupt?
  - Q4. Sessions: where is a new interactive session stored (`~/.kiro/sessions/<id>/sess_<uuid>/`; what is `<id>`: a hash of the cwd?); does `--resume-id sess_<uuid>` (or only `<uuid>`) resume it in the same cwd, and from another cwd? What does `kiro-cli chat --list-sessions --format json` print? What is the exact id string a hook reports versus the directory name?
  - Q5. `--trust-workspace`: with it, a fresh folder shows no trust dialog; without it, capture the dialog to `trust.txt` and record the keys that accept it. Does an agent file in `~/.kiro/agents` with hooks need workspace trust to run its hooks?
  - Q6. Permissions: in the agent file with rules `shell allow ["echo *"]` and `shell deny ["rm -rf *"]` and nothing for `touch`, what happens for (a) `echo hi`, (b) `rm -rf x`, (c) `touch y`? Capture the prompt for (c) to `permission.txt` and record the keys that approve once, approve always, and deny, and what the screen shows afterwards. Which rule syntax allows everything under the workspace (`fs_write` with `**`?) and a single absolute folder outside it? What `capability` and `match` forms matched, by trial.
  - Q7. Screens, captured at 160x45 to fixtures: `idle.txt` (fresh session at its input box), `working.txt` (a turn under way: the spinner or status line), `done.txt` (the same session right after the turn, at its input box), and for each, which lines or glyphs a reader can rely on. Also: does a multi-line bracketed paste followed by Enter (150 ms later) submit one message? Does `Esc` interrupt a turn? Does a positional first message (`kiro-cli chat --agent x "do it"`) start the turn at once?
  - Q8. Background work: can Kiro's shell tool run a command in the background and then wake the agent when it finishes (Echo's Orchestrator relies on this with `echoctl wait`)? Test with a command that sleeps 20 s then writes a file, asked to "run it in the background and tell me when it finishes". If there is a background mode, capture the screen while idle with a background command running to `waiting.txt` and note the footer text. Also: what is the longest foreground command the shell tool allows (a timeout setting?), since `echoctl ask` waits up to 600 s and `echoctl wait` up to an hour.
  - Q9. Environment: which environment variables does a running Kiro session set or read that would confuse a nested Kiro (run `env | grep -i kiro` through its shell tool)? 
  - Q10. `messages.jsonl`: list the distinct `payload` types (user text, assistant text, tool call, tool result, anything else) with one redacted example each. This only informs milestone 2.
  - Q11. Usage: how can credits left or used be read without the TUI (`kiro-cli whoami`, a settings key, a command, a file under `~/.kiro`)? Only informs milestone 3.
  - Q12. Are `--model claude-haiku-5.5`, `--effort high` and `--agent` accepted together, and what happens with an unknown model id (error text, exit code, is it before the TUI starts)?
  - Q13. Folders outside the workspace: with `permissions.rules` allowing `fs_read` and `fs_write` for `/tmp/kirospike-outside/**`, can the agent read and write `/tmp/kirospike-outside/x.txt` without a prompt? Without the rule, what does it do?
- verify: `test -f docs/research/kiro-cli-spike.md && head -1 docs/research/kiro-cli-spike.md | grep -q '^Verdict: ' && [ "$(grep -c '^### Q' docs/research/kiro-cli-spike.md)" -ge 13 ] && ls crates/hub/tests/fixtures/kiro/ | grep -q idle && ls crates/hub/tests/fixtures/kiro/ | grep -q working && ! ls ~/.kiro/agents | grep -q echo-spike && ! tmux ls 2>/dev/null | grep -q kirospike && ! pgrep -f 'kiro-cli chat' >/dev/null`
- commit: `Docs: what Kiro CLI's screens, hooks and shell tool do, from a spike`

### T02 The Kiro arm of the adapter
- id: T02
- agent: naruto
- depends_on: T01
- files: `crates/hub/src/cli.rs`
- goal: add `Cli::Kiro` as decided in 0068, following the spike's findings (flags, front-matter shape, rule syntax, session path all come from `docs/research/kiro-cli-spike.md`; where the spike differs from 0068's wording, build what the spike proves works and say so in the commit body). First read the spike's verdict: if it is `NO-GO`, make no change and report `blocked` with the verdict.
- behaviour:
  - `parse("kiro")`, `name()` "kiro", `program()` "kiro-cli" (name and program now differ: check every use of `name()` and `program()` still means the right thing, in particular what is stored in the DB `cli` columns and shown to the app: it must be "kiro"), error strings now say "claude, codex and kiro".
  - `model_arg`: a bare id passes through; `kiro/<id>` strips the prefix; any other `provider/model` is refused with a message naming it and saying to pick another cli, in the style of the existing arms.
  - `has_session(id)`: true when a directory named `<id>` or `sess_<id>` (as the spike found the id to look) exists at `$KIRO_HOME/sessions/*/` (default `~/.kiro/sessions/*/`); empty id is false. Provide a helper taking the base dir so tests can use a temp dir.
  - `args(hub, start)` for Kiro: write the agent file (below) and return `chat --v3 --agent echo-<hash> [--model <m>] [--effort <e>] --trust-workspace` plus, for a resume, `--resume-id <session id>`, then `start.extra`, then, when `start.first` is set, `--` is NOT used unless the spike shows `kiro-cli chat` accepts it; otherwise pass the first message as the positional INPUT last (watch for a message starting with `-`: the spike's Q7/Q12 results decide how to protect it).
  - New field `pub cwd: Option<PathBuf>` on `Start` (the agent's working directory), used for permission rules; `Start` derives `Default` so existing constructors compile.
  - The agent file: Markdown with front matter and the prompt as the body, written to `$KIRO_HOME/agents/` (default `~/.kiro/agents/`), created if missing, named `echo-<16 hex chars of a stable hash of the full content with a placeholder name>.md`. Use a stable hash (FNV-1a 64 implemented inline, or a crate already in `Cargo.lock`; not `DefaultHasher`). Write it only when no file of that name exists (content-named, so never rewritten with other content); write atomically (temp file in the same folder, then rename). Front matter: `name`, `description: Echo <orchestrator|session|worker>`, `model` (when given), `tools` (map `start.tools` Claude names: Bash to `shell`, Read to `read`, Edit and Write and NotebookEdit to `write`, WebFetch and WebSearch to `web`, ToolSearch ignored, anything else ignored; empty means `["*"]`), `permissions.rules` (below), `hooks`.
  - Hooks in the file (use the exact shape the spike proved): `SessionStart` runs `echoctl notify` for every agent; for a Worker also `Stop` runs `echoctl notify`. Prefix the command with `HUB_WORKER=... HUB_AGENT=...` only if Q2 showed the environment is not inherited (then `Start` also needs `worker_id` and `agent_id` fields; add them as `Option<i64>` and say so in the commit).
  - Rules for a Worker (`start.worker`): allow `fs_read` everywhere; allow `fs_write` and `shell` in `start.cwd` and in every `start.dirs` folder (and the shell commands the spike showed are needed for the checkout); deny `shell` for `rm -rf *`, `rm -fr *`, `git reset --hard*`, `sudo *`, `curl * | sh`, `curl * | bash`, `wget * | sh`, `wget * | bash`. Rules for an Orchestrator or a Normal session: allow `fs_read` and `fs_write` for `start.dirs` (the hub dir and the memory dir) so it never prompts for them, nothing else (its other prompts reach Needs you through the screen reader).
  - `start.plugins` are ignored for Kiro. `start.title` is ignored.
- tests (in `cli.rs`'s test module): `parse`/`name`/`program`; `model_arg` accepted and refused cases; `has_session` against a temp dir tree for both id spellings; `args` for a new Orchestrator, a new Worker (agent file content asserted: hooks, deny rules, body is the prompt, tools mapped), a resume, and a first message starting with `-`; the same `Start` twice gives the same agent file name and does not rewrite it; two different prompts give two names. Use `KIRO_HOME` pointed at a temp dir in the tests (set per test through a helper that takes the dir, not by mutating the process environment, so tests stay parallel-safe).
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl cli:: 2>&1 | tail -5`
- commit: `Daemon: Kiro runs as a third agent CLI behind the adapter (features/0068)`

### T03 Reading Kiro's screen
- id: T03
- agent: naruto
- depends_on: T02
- files: `crates/hub/src/screen.rs`, `crates/hub/src/cli.rs` (wiring only), `crates/hub/tests/fixtures/kiro/` (read)
- goal: `kiro_look`, `kiro_prompt_lines` and `kiro_turn_ended` in `screen.rs`, written against the captured fixtures, and wired into `Cli::look`, `prompt_lines`, `turn_ended`, `trust_keys` (with `--trust-workspace` there should be no trust dialog; `trust_keys` returns what the spike's `trust.txt` showed, in case it still appears). Follow the module's rules: only the bottom of the screen counts (`RECENT`), a quoted prompt or spinner in the transcript must not count, `Look::Waiting` only when the spike (Q8) found a footer for background work.
- If Kiro's approve and deny keys are not Enter and Esc (spike Q6), add `Cli::approve_keys()` and `Cli::deny_keys()` (defaults Enter and Esc) and make `daemon.rs::decide` and `decide_agent` use them; the denial note typing stays as is.
- tests: one test per fixture (`idle`, `working`, `done`, `permission`, and `trust`/`waiting` if captured) asserting the `Look`; negative tests (the same words quoted higher up in the transcript are not a prompt); `kiro_prompt_lines` returns the command asked about; `kiro_turn_ended` true on `done.txt`, false on `working.txt`. Load fixtures with `include_str!`.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl screen:: 2>&1 | tail -5`
- commit: `Daemon: read Kiro's screen for prompts, working, waiting and idle`

### T04 The hook tells the daemon Kiro's session id
- id: T04
- agent: naruto
- depends_on: T02
- files: `crates/hub/src/main.rs` (`notify`), `crates/hub/src/daemon.rs` (only if the `session`/`notify` handlers need it), `crates/hub/tests/daemon.rs`
- goal: `echoctl notify` handles Kiro's hook events: `SessionStart` and its alias `agentSpawn` (the documented sample shows `hook_event_name: "agentSpawn"`; use what the spike's `hook-*.json` files show) record `session_id` through the `session` RPC with the id spelled the way `Cli::Kiro.has_session` and `--resume-id` expect (strip or add `sess_` as the spike found); `Stop` reports the idle blocker as for Codex. Claude's and Codex's events behave exactly as before.
- tests: factor the event-to-call mapping into a pure function if `notify` is not testable now, and unit-test it with the spike's real JSON samples as fixtures (copy them to `crates/hub/tests/fixtures/kiro/hook-*.json`); add a `tests/daemon.rs` case that sends a Kiro-shaped SessionStart through `echoctl notify` with `HUB_WORKER` set and checks the Worker's stored session id changes, following how existing tests drive Codex's hook if there is one.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | tail -8`
- commit: `Daemon: Kiro's SessionStart and Stop hooks report the session id and the idle blocker`

### T05 Wire Kiro into the launch paths, and tell it the tools it has
- id: T05
- agent: naruto
- depends_on: T03, T04
- files: `crates/hub/src/daemon.rs`, `crates/hub/src/cli.rs`, `crates/hub/src/launch.rs`, `crates/hub/src/profile.rs`, `<hub dir>/kiro-notes.md` (new; the hub dir is the folder holding `orchestrator.md` and `worker-contract.md`, find it with `paths::hub_dir()`), `orchestrator.md` and `worker-contract.md` only if a sentence is wrong for every CLI
- goal:
  1. Set `Start.cwd` where `Cli::args` is called (`open_agent` with the agent's home, `spawn_for` with the Worker's cwd) and `worker_id`/`agent_id` if T02 added them.
  2. Look at the three hard-coded `cli::Cli::Claude` fallbacks named in research.md A (`recover`, the test-agent branch, the side shells) and the Orchestrator default model (`cli == Claude` only). Change only what is wrong for Kiro: a recovered Kiro agent must come back as Kiro. Side shells stay plain shells.
  3. `is_agent_var`: add the Kiro markers from spike Q9, if any, so a Kiro agent never inherits another's.
  4. `kiro-notes.md`: what a Kiro agent needs to know that the Claude-worded prompts assume otherwise, with a `## Orchestrator` and a `## Worker` section. The adapter appends the matching section to the prompt body. Content is driven by the spike: which Kiro tool is the shell and the file reader and writer (Worker Contract says "Bash tool" and "Read tool"), how to run `echoctl ask` within the shell tool's timeout limit (Q8), and for the Orchestrator how to wait for Workers: a background `echoctl wait` if Q8 proved Kiro wakes the agent, otherwise a foreground `echoctl wait --timeout <seconds under the shell limit>` in a loop. If Kiro cannot wait at all (neither works), write the Orchestrator section as "Orchestrators do not run on Kiro yet", make `open_agent` refuse `kind=orchestrator` with `cli=kiro` with that message (before anything is created), and say so in the commit.
  5. A Kiro agent that is `Idle` and unchanged for 60 s already becomes an idle blocker through `watch`; confirm that path works for Kiro's `Look::Idle` with a unit or daemon test using the fixtures if that is feasible without a real Kiro; otherwise note the check in T08.
- tests: add unit tests for the notes selection (Worker vs Orchestrator section), and a daemon test that an agent stored with `cli = kiro` is recovered with `Cli::Kiro` (find how `recover` is tested; if there is no such test, test the pure function you change).
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | tail -8`
- commit: `Daemon: Kiro agents get their working folder, their tool notes, and come back as Kiro after a restart`

### T06 Profiles, settings, README and CONTEXT
- id: T06
- agent: naruto
- depends_on: T05
- files: `crates/hub/src/profile.rs` (tests only unless needed), `crates/hub/src/settings.rs` (only if `cli` is validated separately), `README.md`, `CONTEXT.md`, `crates/hub/tests/daemon.rs`
- goal: `cli: kiro` is accepted wherever `claude` and `codex` are: a Profile front matter, `settings.json` (`{"cli":"kiro","model":"claude-sonnet-5.5"}`), the repo's `.echo/settings.json`, `echoctl worker start --cli kiro`, and the daemon's `settings.set`/`settings.get` for `cli`, `model` and `orchestratorModel`. `echoctl profile list` shows `kiro claude-sonnet-5.5` for a Profile that says so. A bad Kiro model (`openai/gpt-5`) fails the start before a worktree is made, as for the other CLIs. README's CLI paragraph (README.md ~L55-72) says the CLIs are `claude`, `codex` and `kiro`, how Kiro names models, what needs `kiro-cli` signed in, what is unsupported for Kiro (chat tab, usage bar, stats, renewal), and that with `cli: kiro` the human should also set `orchestratorModel` to a Kiro id (an `anthropic/...` value is refused). CONTEXT.md names Kiro where it lists the CLIs.
- tests: profile parse accepts `cli: kiro` and still refuses `gemini`; a daemon test that `worker start --cli kiro --model openai/gpt-5` fails before creating a worktree (use the test daemon; no real Kiro runs because the failure is before the spawn).
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | tail -8 && grep -q kiro README.md && grep -q -i kiro CONTEXT.md`
- commit: `Docs: Kiro is a CLI Profiles, settings and echoctl accept`

### T07 The app offers Kiro and names its models
- id: T07
- agent: naruto
- depends_on: T06
- files: `app/Sources/HubCore/Models.swift` (`agentCLIs`), `app/Sources/HubApp/AgentSettings.swift`, `app/Sources/HubApp/ContentView.swift` (`AgentLine.short`, stats footnote), `app/Sources/HubApp/ChatView.swift` (composer placeholder, unsupported-chat text), `app/Sources/HubApp/AppModel.swift` (model list), `app/Tests/`
- goal: add `"kiro"` to `agentCLIs` so the Settings CLI picker offers it (`AgentSettings.swift` ~L115-140) and the Profile CLI picker too; the hint under the model field says Kiro takes its own ids such as `claude-sonnet-5.5`; `AgentLine.short` shortens `claude-opus-5.5` (dot) to `opus` as it does the dashed form; where the app says "Claude" for an agent whose CLI it knows is not claude (composer placeholder "Reply to Claude…", the unsupported-chat message, the stats footnote "From Claude Code transcripts; Codex Workers are not counted"), name the right CLI or stay neutral. Check how the snapshot carries an agent's cli (`Agent`/`WorkerRow` in `Models.swift`); use it if it is there, and if it is not, do not add a daemon field in this task: keep the label neutral. Keep the look rules (ui-ux decisions); no new views.
- tests: if a label helper is added to HubCore, test it in `app/Tests` (Swift Testing); keep the 66 existing tests green.
- verify: `make -C app test 2>&1 | tail -3 && make -C app app 2>&1 | grep -E 'error|Built'`
- commit: `Echo: Settings offers Kiro, and a Kiro agent's models and labels read right`

### T08 Smoke run on real Kiro, in an isolated daemon
- id: T08
- agent: naruto
- depends_on: T07
- files: none in the repo except `docs/bugs/<next number>-*.md` for any bug found and fixed here, and the fixes themselves
- goal: prove acceptance criterion 4 with real `kiro-cli` on `claude-haiku-5.5`, in an isolated environment, then clean up completely. Steps: build the daemon (`~/.cargo/bin/cargo build -p echoctl`); `export HUB_STATE=/tmp/hubk` and put `target/debug` first on `PATH`; create the throwaway repo `/tmp/hubk-repo-zeta` (git init, one commit); write `/tmp/hubk/settings.json` `{"cli":"kiro","model":"claude-haiku-5.5","orchestratorModel":"claude-haiku-5.5"}`; note the list of `~/.kiro/agents/echo-*.md` before the run.
  1. Worker: `echoctl worker start --repo /tmp/hubk-repo-zeta --profile naruto --cli kiro --model claude-haiku-5.5 --spec "Create hello.txt containing the word hi, commit it, then finish with echoctl done."` (find the exact flags with `echoctl worker start --help`). Check: the Worker row leaves `starting` for `running` (so Look or the session id worked), a `session_id` is stored that `has_session` accepts, `echoctl worker read` shows the screen, and it ends `done` with a Final Report mentioning hello.txt. Record how long it took and any prompt it hit.
  2. Prompt path: start a second Worker whose spec makes it run a command your rules do not allow and are not denied (the spike's `touch y` kind of case), and check it becomes a `permission_prompt` blocker with the prompt text, then `echoctl worker key`/the daemon `decide` approves it with the keys `Cli::Kiro` uses, and it continues.
  3. Resume: stop the daemon without `--force` and start it again; the Worker/agent comes back as Kiro; `echoctl worker resume` (or the equivalent) resumes by `--resume-id` and the CLI continues the same session (record the evidence).
  4. Orchestrator (skip with a note if T05 made Orchestrators refuse Kiro): open an Orchestrator on Kiro in the repo with the request "Start one naruto Worker to create world.txt, wait for it, and tell me when it is done"; check it starts the Worker, `echoctl wait` returns its message, and it reports. Give it at most 10 minutes.
  5. Fix what is broken (small fixes only, with a test and a `docs/bugs/` file per `docs/bugs/README.md`); anything larger is reported `blocked` with evidence and what would unblock it.
  6. Clean up in this order: kill tmux sessions whose start command contains `/tmp/hubk`, `echoctl shutdown --force` with the test env, `pgrep -f 'kiro-cli'` shows none of the smoke's, delete `/tmp/hubk*`, delete the `~/.kiro/agents/echo-*.md` files that were not in the before list (only those).
- verify: `! ls /tmp | grep -q '^hubk' && ! tmux ls 2>/dev/null | grep -q hubk && git status --short | grep -v '^$' | wc -l | grep -q '^0$'` and the report quotes the evidence for steps 1 to 4.
- commit: only if fixes were made: `Daemon: <what the smoke run found>`

### T09 Final check
- id: T09
- agent: naruto
- depends_on: T08
- files: none expected
- goal: from a clean checkout state run the whole suite and confirm the acceptance criteria 1, 2, 3, 5 of big-picture.md; list in the report any decision a later session could undo by accident that has no file yet (for example the content-named agent files, `kiro-notes.md`, the deny rules) and write each as a new `docs/decisions/features/NNNN-*.md` (next numbers after 0068, one decision per file, format in `docs/decisions/README.md`). Do not edit 0068.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | tail -3 && make -C app test 2>&1 | tail -2 && git status --short | wc -l | grep -q '^0$'`
- commit: `Docs: decisions for what the Kiro adapter chose` (only if files were added)

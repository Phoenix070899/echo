Verdict: GO

# Kiro CLI spike: screens, hooks and the shell tool

Date: 2026-11-13. Written for the Kiro adapter, screen readers and hook handling (decision features/0068, plan `docs/plans/2026-11-13-kiro-cli-provider/`).
Every result below comes from real `kiro-cli chat --v3` runs in tmux at 160 columns by 45 rows, always with `--model claude-haiku-5.5`, in the throwaway repo `/tmp/kirospike-repo` (a `git init` with one commit, branch `main`).
Screen fixtures are in `crates/hub/tests/fixtures/kiro/` (`*.txt`) and real hook payloads in `crates/hub/tests/fixtures/kiro/hook-<Event>.json`; the home folder is written `/Users/me` in them.

Version caveat: the binary updated itself from 3.2.1 to 3.3.0 at 16:28 while the spike ran (`kiro-cli --version` now prints `kiro-cli 3.3.0`; `~/Library/Application Support/kiro-cli/run/` holds `chat-cli-3.2.1` and `chat-cli-3.3.0`).
Launches during the spike alternated between the two (`KIRO_VERSION=3.2.1` or `3.3.0` in the hook environment, for the same command line). Every behaviour below was observed on both, or on one with no difference seen on the other. Do not pin on the version.

Verdict reasoning: Q2 passes (the session id arrives through a `SessionStart` hook, with one timing caveat), Q3 and Q6 pass (states and prompts are readable from the screen). Findings later tasks must plan around: **Q8 FAILS** (Kiro's background shell never wakes the agent), `SessionStart` fires on the first prompt rather than at start, and a first message that begins with `-` is lost or misparsed.

## Summary

| Q | Result | One line |
|---|---|---|
| Q1 | PASS | `--agent <name>` loads `~/.kiro/agents/<name>.md` or `<cwd>/.kiro/agents/<name>.md`; body reaches the model; a file path is refused |
| Q2 | PASS | `SessionStart` fires on the first prompt of a new session (not at TUI start, not on resume); stdin has `session_id` `sess_<uuid>`; `HUB_*` inherited |
| Q3 | PASS | `Stop` fires after every completed turn; not after an `Esc` cancel or an errored turn |
| Q4 | PASS | `~/.kiro/sessions/<sha256(realpath cwd)[:16]>/sess_<uuid>/`; `--resume-id` accepts `sess_<uuid>` or bare `<uuid>`, from any cwd |
| Q5 | PASS | `--trust-workspace` skips the dialog; dialog captured; global agent hooks run without trust in headless mode |
| Q6 | PASS | allow, deny and ask all behave; Enter approves once, Down+Enter denies once; `**` matches everywhere, an absolute glob limits it |
| Q7 | PASS | idle, working, done are distinct; paste+Enter is one message; `Esc` cancels; positional first message works, but not when it starts with `-` |
| Q8 | FAIL | `run_in_background=true` only appends `&`; no job id, no wake-up, no footer; foreground default timeout 120 s, `timeout` parameter up to 1,800,000 ms |
| Q9 | NOTE | `KIRO_SESSION_ID`, `KIRO_TUI_READY_*`, `KIRO_CHAT_CLI_BIN*` and about 30 more `KIRO_*` variables are set; shell tool inherits `HUB_*` |
| Q10 | NOTE | 15 payload types in `messages.jsonl`; list below |
| Q11 | NOTE | No CLI command or file; `/usage` in the TUI, the per-turn `Credits:` line, and the ACP method `_kiro/account/getUsage` |
| Q12 | PASS | Flags combine; an unknown model starts the TUI and fails at the first prompt (headless exit 1) |
| Q13 | PASS | `/tmp/kirospike-outside/**` rules allow read and write with no prompt; without them every outside write asks |

### Q1
**PASS.** A Markdown agent file in `~/.kiro/agents` is picked by name and its body is the system prompt.

Command: `kiro-cli chat --v3 --agent echo-spike-a --model claude-haiku-5.5 --trust-workspace` (cwd `/tmp/kirospike-repo`), then the prompt `What is the secret codeword? Reply with just the codeword.`
Observed: the answer line `• PINEAPPLE-42`; the codeword exists only in the file body. The footer shows the agent id `echo-spike-a`; `session.json` has `"agentMode": "echo-spike-a"`; `messages.jsonl` has a `session_start` entry whose `content` is the body followed by an appended `<hook_output_channel>…` block.
Headless check: `kiro-cli chat --v3 --no-interactive --trust-workspace --agent echo-spike-a --model claude-haiku-5.5 "What is the secret codeword? Just the codeword."` printed `PINEAPPLE-42`.

`--agent` needs the **name** (the `name:` front-matter value, which equals the file stem here). A path is refused:
```
$ kiro-cli chat --v3 --no-interactive --trust-workspace --agent ~/.kiro/agents/echo-spike-a.md "x"
Error: agent "/Users/me/.kiro/agents/echo-spike-a.md" not found, stopping (exit 4)
$ kiro-cli chat ... --agent .kiro/agents/echo-spike-b.md "x"     -> same error, exit 4
$ kiro-cli chat ... --agent nope-agent "hi"                       -> Error: agent "nope-agent" not found, stopping (exit 4)
```
A workspace-local file works too: `/tmp/kirospike-repo/.kiro/agents/echo-spike-b.md` (codeword `KIWI-7`) with `--agent echo-spike-b --trust-workspace --no-interactive` printed `KIWI-7`. So a generated file may live in `<cwd>/.kiro/agents/` or `~/.kiro/agents/`. (Not tested: a local agent in a folder that was never trusted, because the interactive dialog cannot be passed without saving trust. `--trust-workspace` was used.)
`--model` on the command line overrides the file's `model:` (file said `claude-haiku-5.5`, `--model nonexistent-model-9` showed `nonexistent-model-9` in the footer).

Front matter proven to load (a complete working file is at the end of this document).

### Q2
**PASS, with a timing caveat.** The `SessionStart` hook in the agent file fires, with the session id.

Timing, measured on interactive runs:
- The TUI started at 16:28:15; after 10 s idle `/tmp/kirospike/` still had no `hook-SessionStart.json`. The session directory and `session.json` already existed. The hook ran at 16:29:06, the moment the first prompt was submitted. So **the id is not known until the first user message**. With a positional first message (`kiro-cli chat --agent x "do it"`) the hook fires at the start of that turn.
- On `--resume-id` the hook does **not** fire again. Three resumes, each followed by a prompt: same cwd without `--agent` (only `Stop` fired), another cwd (only `Stop`), and with `--agent echo-spike-h` (`UserPromptSubmit`, `Stop`, then `SessionEnd` at `/quit`; no `SessionStart`). The agent is restored from the session without `--agent`: the footer still said `echo-spike-a`, and the agent's `Stop` hook ran. So on resume Echo keeps the id it already has.

stdin, exactly (`crates/hub/tests/fixtures/kiro/hook-SessionStart.json`):
```
{"session_id":"sess_6a2fda8e-84a4-4c82-acff-71eb59863c06","hook_event_name":"SessionStart","cwd":"/private/tmp/kirospike-repo"}
```
- `hook_event_name` is `SessionStart` (the trigger name written in the file; not the documented alias `agentSpawn`).
- `session_id` is `sess_<uuid>`, the same string as the session directory name and as `--resume-id`'s argument.
- `cwd` is the real path (`/private/tmp/...`, not `/tmp/...` on macOS); canonicalize before comparing.
- The hook's environment also has `KIRO_SESSION_ID=sess_…` (same value), so a hook can read the id from the environment instead of stdin.

Environment: the tmux command was `HUB_WORKER=w99 HUB_AGENT=7 kiro-cli chat …`. The hook saw `HUB_WORKER=w99` and `HUB_AGENT=7` (`env | grep -E '^(HUB_|KIRO|ECHO_)'` in `hook-env.txt`). They are inherited, so `echoctl notify` in a hook sees the Worker id without help.
When not inherited, the command string can carry them. Run with `env -u HUB_WORKER -u HUB_AGENT kiro-cli chat --v3 --no-interactive --trust-workspace --agent echo-spike-z …`, with the file's hook `command: HUB_WORKER=w42 HUB_AGENT=3 /tmp/kirospike/hook.sh SessionStart`: the hook saw `HUB_WORKER=w42` and `HUB_AGENT=3`. The command runs through a shell, so an `VAR=value cmd` prefix works.

Other events (real payloads, one fixture each):
```
UserPromptSubmit {"session_id":"sess_934e96d5-…","hook_event_name":"UserPromptSubmit","cwd":"/private/tmp/kirospike-repo","prompt":"Run exactly this shell command: echo hello-hooks"}
PreToolUse       {"session_id":"…","hook_event_name":"PreToolUse","cwd":"…","tool_name":"execute_bash","tool_input":{"command":"echo hello-hooks","description":"Print hello-hooks to stdout","cwd":null,"run_in_background":false,"timeout":null}}
PostToolUse      {"session_id":"…","hook_event_name":"PostToolUse","cwd":"…","tool_name":"execute_bash","tool_input":{…same…},"tool_response":"Output:\nhello-hooks\n\n\nExit Code: 0"}
Stop             {"session_id":"…","hook_event_name":"Stop","cwd":"…"}
SessionEnd       {"session_id":"…","hook_event_name":"SessionEnd","cwd":"…","reason":"shutdown"}
```
`SessionEnd` fired on `/quit` (reason `shutdown`). The `matcher: shell` on `PreToolUse`/`PostToolUse` matched the tool `execute_bash`. Hook exit code was 0 in every test; blocking behaviour was not tested.
`PreToolUse` fires for tool calls the rules already allow. It was not observed for a call that stops at a permission prompt.

### Q3
**PASS.** `Stop` fires at the end of every turn that finishes normally.

Interactive agent `echo-spike-a` over a session of six turns (codeword, `echo hi`, `touch y` with approval, a refused `ls`, a rule-denied `rm -rf x`, a 600-word story cancelled with `Esc`): `hook-all.log` had one `SessionStart` and **five** `Stop` lines. stdin of each (`hook-Stop.json`):
```
{"session_id":"sess_6a2fda8e-84a4-4c82-acff-71eb59863c06","hook_event_name":"Stop","cwd":"/private/tmp/kirospike-repo"}
```
No stop reason, no transcript path, no turn id.
- Turn ended by `Esc` (screen: `• Cancelled streaming`): **no** `Stop`. `messages.jsonl` has `turn_end` with `stopReason: "cancelled"`.
- Turn that failed (unknown model): **no** `Stop`; `stopReason: "error"`.
- Turn where the human or a rule denied a tool: the model then answers and the turn ends `end_turn`, so `Stop` fires.
- Checked in `messages.jsonl` over every spike session whose agent had a `Stop` hook: all 23 `end_turn` turns had a `ContextualHookInvoked` for it; the 2 `cancelled` and 2 `error` turns had none.
So "agent is waiting for the human" cannot be derived from `Stop` alone: after a cancel or an error the screen is idle but no hook came. The screen reader must cover those.

### Q4
**PASS.** Layout of a new interactive session, observed:
```
~/.kiro/sessions/a44897a43362370a/                     <- sha256("/private/tmp/kirospike-repo")[:16] (the real path)
~/.kiro/sessions/a44897a43362370a/.index/.lock
~/.kiro/sessions/a44897a43362370a/sess_6a2fda8e-84a4-4c82-acff-71eb59863c06/{.lock,session.json,messages.jsonl}
~/.kiro/session-index/a44897a43362370a.jsonl            <- {"op":"add","sessionPath":"a44897a43362370a/sess_6a2f…","at":1794562097368}
~/.kiro/session-leases/sess_6a2fda8e-….lease            <- JSON {"v":1,"pid":…,"parentPid":…,"instanceId":…,"hostId":…,"acquiredAt":…,"token":…,"clientName":"kiro-cli"}; exists while the session is open, removed after /quit
```
`<id>` is the first 16 hex characters of the SHA-256 of the **real** (symlink-resolved) cwd: checked for `/private/tmp/kirospike-repo` (`a44897a43362370a`) and `/private/tmp/kirospike-trust` (`86b016d8be167d63`, also the name under `workspace-roots/`). The session directory name equals the id a hook reports (`sess_<uuid>`, including the prefix). The directory appears at TUI start (before any prompt); `messages.jsonl` appears with the first turn.
`session.json` fields seen: `schemaVersion`, `dataModelVersion`, `id`, `title` (`"New Session"` until the first turn, then a model-written title such as `"What is the secret codeword? Reply with just the codeword"`), `agentMode` (the agent name), `workspacePaths`, `rootPaths`, `createdAt`, `lastModifiedAt`, `modelId`, `autopilot` (true), `effortLevel`, `_meta.kiro.settings`, `_meta.kiro.modeId`.

Resume (all with `--trust-workspace --model claude-haiku-5.5`):
- Same cwd, `kiro-cli chat --v3 --resume-id sess_6a2fda8e-84a4-4c82-acff-71eb59863c06`: PASS; the screen replays the whole history (`resumed.txt`), the footer keeps the agent (`echo-spike-a`) and model.
- Bare uuid, `--resume-id 6a2fda8e-84a4-4c82-acff-71eb59863c06`: PASS.
- Another cwd (`/tmp/kirospike-other`): PASS. While loading, the box shows `›  Initializing · type to queue a message` and the footer lacks the agent/model; after a few seconds it is the normal idle screen with the new cwd on the right. The session stays in its original `sessions/<hash>/` bucket and `workspacePaths` is unchanged; hooks report the **new** cwd (`"cwd":"/private/tmp/kirospike-other"`).
- On `/quit` Kiro prints `Session ended.` then `Resume with: kiro-cli --resume-id sess_6a2fda8e-84a4-4c82-acff-71eb59863c06`.

`kiro-cli chat --list-sessions --format json` (cwd `/tmp/kirospike-repo`), real output:
```
[{"cwd":"/private/tmp/kirospike-repo","sessions":[{"sessionId":"sess_6a2fda8e-84a4-4c82-acff-71eb59863c06","source":"v3","title":"What is the secret codeword? Reply with just the codeword","updatedAt":"2026-11-13T09:31:32.675Z","executionTarget":"local","status":"idle"},{"sessionId":"1df8cd0f-77e5-42ee-92a3-7f983c7cd668","source":"v3","title":"Decode Encoded String","updatedAt":"2026-09-30T18:51:29.838Z","executionTarget":"cloud-sandbox","status":"idle"}],"complete":true}]
```
It lists cloud sessions too (`executionTarget` `cloud-sandbox`, id without the `sess_` prefix). `status` stayed `"idle"` while a session was open and running, so it is no liveness signal; the `session-leases/<id>.lease` file is (present while open). `--list-sessions` without `--format json` prints coloured text.
`~/.kiro/sessions/cli/sess_<uuid>.history` is the prompt-history file of an older session, not needed.
A session exists when `~/.kiro/sessions/*/<id>/` does (as decision 0068 says); `ls ~/.kiro/sessions/*/sess_<uuid>` was used.

### Q5
**PASS.**
- `--trust-workspace` on `/tmp/kirospike-repo` (never trusted): no dialog, TUI at the idle box in about 8 s. It is per launch; nothing is saved.
- Without it, in a fresh folder `/tmp/kirospike-trust` (`trust.txt`):
```
 ────────────────────────────────────────────────────────────────────────────────
 Trust this workspace?
 ────────────────────────────────────────────────────────────────────────────────
 /private/tmp/kirospike-trust
 This folder can contain hooks, agents, MCP servers and workflows that run commands on your machine. Only trust folders you know.
 Trusting lets Kiro use this workspace's configuration. Kiro will be able to read, edit, and execute files here.
 ❯ Trust, continue
   Don't trust, exit
 ────────────────────────────────────────────────────────────────────────────────
 esc to exit · ↑↓ to navigate · ↵ to select
 Revoke later by removing workspaceTrusted from /Users/me/.kiro/workspace-roots/86b016d8be167d63/permissions.yaml
```
- Keys: `Enter` on the default first row (`Trust, continue`) accepts (not run, to keep `~/.kiro` untouched: it writes `workspaceTrusted: true` to `~/.kiro/workspace-roots/<hash>/permissions.yaml`, the format of the human's existing `4a25fb8d81376615/permissions.yaml`: `rules: []` and `workspaceTrusted: true`). `Down` then `Enter` declines: the line `Not trusted: /private/tmp/kirospike-trust. Kiro exited without loading this folder.` is printed and `kiro-cli` exits with status 0.
- A global agent with hooks does not need trust to run them in headless mode: in the untrusted `/tmp/kirospike-trust`, `kiro-cli chat --v3 --no-interactive --agent echo-spike-a --model claude-haiku-5.5 "Reply with the single word ok."` printed `ok` with no dialog, and both `SessionStart` and `Stop` hooks ran. The interactive TUI always asks first, and exits if declined, so a global agent's hooks never run there without trust. Echo passes `--trust-workspace`, so this never arises.

### Q6
**PASS.** Agent `echo-spike-a`: `shell allow ["echo *"]`, `shell deny ["rm -rf *"]`, nothing for `touch`. Fixtures: `permission.txt`, `permission-fsread.txt`, `permission-fswrite.txt`, `permission-always.txt`, `allowed-once.txt`, `rejected.txt`, `denied-by-rule.txt`.

(a) `Run exactly this shell command and show its output: echo hi` ran with no prompt: `• Shell echo hi`, `    ╰ description=Print the word hi, run_in_background=false`, `    ╰ hi`, then `• Output:` / `  hi`.
(b) `rm -rf x`: the first time the model refused to guess and asked to run `ls -la x` (which prompted); when told to run `rm -rf x` exactly, the shell tool result was, with no prompt (`denied-by-rule.txt`):
```
• Shell rm -rf x
    ╰ description=Delete the x folder in the workspace root, cwd=/private/tmp/kirospike-repo, run_in_background=false
    ╰ Output:
      Blocked by a permission rule (deny shell matching "rm -rf *"); the user did not reject it. Source: agent-profile.
      Exit Code: -1
```
The folder `x` was still there. `messages.jsonl` shows the tool call with `status: "denied"`.
(c) `touch y`: prompts (`permission.txt`):
```
  Run exactly this shell command: touch y
↓ Shell touch y
    ╰ description=Create empty file named y, cwd=/private/tmp/kirospike-repo, run_in_background=false
────────────────────────────────────────────────────────────────────────────────
 Create empty file named y requires approval
 shell → touch y
 ❯ Allow once
   Deny once
   Create allow rule to approve future similar actions
   Create deny rule to block future similar actions
────────────────────────────────────────────────────────────────────────────────
 esc to close · ↑↓ to navigate · ↵ to select · Tab to edit
```
`touch y` raised a **second** prompt after the first was approved, `fs_read → .` (`permission-fsread.txt`): reading the working folder needs its own rule when the agent file has no `fs_read` rule. Add `fs_read` allow for the workspace or the prompts double.

Keys (tmux names), tried one by one on these prompts:
- **Approve once**: `Enter` (the cursor starts on `Allow once`). After it: the line becomes `• Shell touch y` (no `↓`), the model's reply, and the idle screen (`allowed-once.txt`); the file was created.
- **Deny once**: `Down`, `Enter`. Screen: `• Rejected ls -la x 2>&1`, then the model says it was declined (`rejected.txt`). The tool result in `messages.jsonl`: `The user rejected this tool call.`, `Exit Code: -1`. The turn goes on and ends normally.
- **Approve always / deny always**: `Down Down Enter` (or `Down Down Down Enter`) opens a second dialog (`permission-always.txt`):
```
 Create allow rule: /private/tmp/kirospike-outside/x.txt
 fs_write → /private/tmp/kirospike-outside/x.txt
 Scope:  [session]   workspace    user   (s to cycle scope)
 ❯ Trust "/private/tmp/kirospike-outside/x.txt"    exact match · session
   Allow a folder for this session…                /private/tmp/kirospike-outside
   Trust entire tool (Write)                       session
 esc to go back · ↑↓ to navigate · ↵ to select · s to cycle scope · Tab to edit
```
  `Enter` on the first row at scope `session` allowed the call and kept nothing on disk (`~/.kiro/workspace-roots/` unchanged); scope `workspace`/`user` (`s`) would write files under `~/.kiro` and was not used.
- Plain letters `y`, `1`, `a` do nothing on the prompt; only arrows, `Enter`, `Esc`, `Tab`, `s`.
- `Esc` on the prompt cancels the whole tool call and turn: screen `• Cancelled touch esc1`, `▸ Credits: turn 0.01 | Time: 4s`, idle box (default agent, `touch esc1` never ran). It is not a deny that lets the model answer.
- `messages.jsonl` records the prompt as `pending_interaction` with options `accept`/`always-accept`/`reject`/`always-reject` and the resolution as `interaction_resolved` (`selectedOption`).

**fs_write prompt** (`permission-fswrite.txt`, extra note): for a file outside the workspace the diff preview is shown above the dialog, and the resource is the real path:
```
↓ Write /tmp/kirospike-outside/x.txt
    added 1 line in x.txt
     1+  hello
────────────────────────────────────────────────────────────────────────────────
 Write File requires approval
 fs_write → /private/tmp/kirospike-outside/x.txt
 ❯ Allow once
 …
```
Inside the workspace the resource is **relative**: `fs_write → w1.txt` for `/tmp/kirospike-repo/w1.txt`. Outside it is absolute and symlink-resolved (`/private/tmp/...`).

**Rule syntax by trial** (agent files `echo-spike-d` to `echo-spike-g`; the shape is the one in the example at the end):
- `capability: fs_write` + `match: ["**"]` allowed a write inside the workspace and also `/tmp/kirospike-other/z.txt` outside it, with no prompt. So `**` means everything, not "under the workspace".
- `match: ["/tmp/kirospike-repo/**"]` (an absolute glob of the workspace) allowed `/tmp/kirospike-repo/w3.txt` and still prompted for `/tmp/kirospike-other/z2.txt`. This is the form for "the workspace, and nothing else". A single absolute outside folder is the same: `["/tmp/kirospike-repo/**", "/tmp/kirospike-outside/**"]`.
- The `/tmp/...` form matched although Kiro reports the file as `/private/tmp/...`; globs written with the path as the caller gave it (the symlink form) matched. Real checkouts under `/Users/…` have no symlink.
- With only the outside-folder rules (agent `d`), a workspace write `/tmp/kirospike-repo/w1.txt` still prompted (`fs_write → w1.txt`).
- `shell` `match: ["echo"]` did **not** allow `echo hi2` (it prompted); `["ls *"]` allowed plain `ls` and `ls -la`; `["touch *"]` allowed `touch t1`; `["date"]` allowed `date`. So `"cmd *"` matches the command with or without arguments, and a bare `"cmd"` matches only that command with no arguments.
- `effect: deny` wins and shows the `Blocked by a permission rule (deny shell matching "rm -rf *")` result; `effect: allow` skips the prompt; no matching rule prompts. `effect: ask` was not exercised.
- Tool names in `tools:` (`read`, `write`, `shell`) map to the capabilities `fs_read`, `fs_write`, `shell`; the model's calls were `read_file`, `fs_write`, `execute_bash`.

### Q7
**PASS.** Screens at 160x45, all taken with `tmux capture-pane -p` (trailing blanks trimmed; 45 lines each).

Layout: the screen is **not bottom-anchored**. A fresh session paints the Kiro logo (rows 1 to 11), then the `▸ What's new` block, then a horizontal rule, the status footer and the input box directly below the content; they move down as content grows. Readers must scan for the **last** lines, not fixed rows. (The behaviour once content passes 45 rows was not examined; the story turn that did was cancelled at 20 rows.)

`idle.txt` (fresh session at its input box):
```
▸ What's new   ctrl+o to expand
  Approve for me, cloud sessions, memory, local sandbox and specs.

────────────────────────────────────────────────────────────────────────────────
echo-spike-a · claude-haiku-5.5 · thinking · medium · ◔ 1%                       /private/tmp/kirospike-repo · (main)

›  ask a question or describe a task ↵
                                                                                 /sessions to resume · /copy to clipboard
```
`working.txt` (a turn under way):
```
  Reply with one line only: the word MULTI, then the number of lines in this message.
  Second line here.
  Third line here.
ᗢ Thinking... (esc to cancel)
────────────────────────────────────────────────────────────────────────────────
echo-spike-a · claude-haiku-5.5 · thinking · medium · ◔ 1%                       /private/tmp/kirospike-repo · (main)
›  Kiro is working · 1s · Type to steer · Ctrl+S to queue
```
`done.txt` (same session right after the turn):
```
• Thought for 1s...
    ╰ Counting the lines in the message: …
• MULTI 3
▸ Credits: turn 0.00 • session 0.00 | Time: 4s
────────────────────────────────────────────────────────────────────────────────
echo-spike-a · claude-haiku-5.5 · thinking · medium · ◔ 1%                       /private/tmp/kirospike-repo · (main)
›  ask a question or describe a task ↵
                                                                                 /sessions to resume · /copy to clipboard
```
What a reader can rely on:
- **Input line**: the last line that starts with `›`. Idle: `›  ask a question or describe a task ↵` (placeholder; if text is typed the placeholder is replaced by the draft, as in `pasted` form `› Reply with one line…`). Working: `›  Kiro is working · <N>s · Type to steer · Ctrl+S to queue` (`<N>s` becomes `1m 48s` after a minute). Startup or resume loading: `›  Initializing · type to queue a message`.
- **Working** is also `ᗢ Thinking... (esc to cancel)` while the model thinks (the glyph cycles `ᗢ ᗥ ᗦ ᗤ ᗧ`, so match `Thinking... (esc to cancel)`), and a two-space-indented `  esc to cancel` line under a running tool (`working-shell.txt`: `• Shell sleep 40`, `    ╰ description=…`, `  esc to cancel`). While streaming text neither line is shown, only the input line (`working-text.txt`), so the input line is the one signal that never disappears.
- **Done**: the line `▸ Credits: turn <t> • session <s> | Time: <N>s` above the rule (no `Credits:` after a cancelled turn: `▸ Time: 4s` then `• Cancelled streaming`).
- **Status footer** (the line under the rule, left): `<agent> · <model> · thinking · <effort> · ◔ <ctx>%`, e.g. `echo-spike-a · claude-haiku-5.5 · thinking · medium · ◔ 1%`; right side `<real cwd> · (<git branch>)`. With the default agent it starts `Default · claude-haiku-5.5 …`. With an unknown model: `echo-spike-c · nonexistent-model-9 · ◔ 1%` (no thinking or effort part). With `--effort high`: `… · thinking · high · ◔ 1%`. The context glyph is `◔` at 1%-2%.
- **Model name in the UI**: `claude-haiku-5.5`, as given.
- **Permission prompt**: lines ` <title> requires approval` and ` <capability> → <resource>`, the four options with `❯` on the selected one, and ` esc to close · ↑↓ to navigate · ↵ to select · Tab to edit`. Match the `requires approval` line together with the hint line and only in the last ~15 lines, because the chat above can quote the words. While the dialog is open the input box is gone.
- **Tool lines**: `• Shell <command>` when done or running, `↓ Shell <command>` while it waits for approval; `• Rejected <command>` (denied once), `• Cancelled <command>` (`Esc`).

Behaviours:
- **Multi-line bracketed paste, then Enter 150 ms later: PASS, one message.** `tmux paste-buffer -p` of `Reply with one line only: …\nSecond line here.\nThird line here.`, `sleep 0.15`, `tmux send-keys Enter`. The input box showed the three lines as typed (no `[Pasted text]` collapse); after `Enter` `messages.jsonl` held **one** `user` entry whose `content` is `'Reply with one line only: the word MULTI, then the number of lines in this message.\nSecond line here.\nThird line here.'`, and the model counted 3 lines (`• MULTI 3`).
- **`Esc` interrupts: PASS.** During streaming: `• Cancelled streaming`, `▸ Time: 4s`, idle box in under 3 s (`cancelled.txt`), no `Stop` hook. During a running tool: `• Cancelled sleep 40` and the process was killed (`pgrep` found no `sleep 40`; `cancelled-tool.txt`).
- **Typing while working** steers the turn (`Type to steer`); `Ctrl+S` queues. Not exercised further.
- **Positional first message** (`kiro-cli chat --v3 --agent echo-spike-a --model claude-haiku-5.5 --trust-workspace 'Reply with the word go.'`): the turn starts by itself, about 4 s after launch (the screen showed the prompt and `• Go`), and `SessionStart` fired then.
- **Positional starting with `-`**: clap reads it as options. In headless mode `"-dash start: reply with the word go"` was taken as `-d` (delete-session) with id `ash start: …`: `Error: chat session ash start: reply with the word go not found`, exit 1. **That is `--delete-session`**, so a message like `-d <id>` could delete a session. `--` works headless: `… -- "-dash start: reply with the word go"` printed `go`, exit 0. **In the interactive TUI `--` does not work**: with `-- '-dash start: …'`, `-- 'Reply with the word go.'` and `-- '- reply with the word go.'` the TUI started at the idle box and the message never arrived (`ps` showed the TUI process launched as `tui.js chat …` without the positional). Rule for the adapter: never pass a first message that starts with `-`; either prefix it with a non-dash character, or start without a message and paste it after the idle box appears.

### Q8
**FAIL.** Kiro's shell tool has no background mode that wakes the agent.

What the tool offers: parameters `command`, `description`, `cwd`, `run_in_background` (default false) and `timeout` (milliseconds). With `run_in_background=true` Kiro just appends ` &` to the command and returns at once.
- Run 1 (agent `echo-spike-a`): `Run this shell command in the background and tell me when it finishes: sleep 20; echo finished > /tmp/kirospike-repo/bg.txt`. The tool line was `• Shell sleep 20; echo finished > /tmp/kirospike-repo/bg.txt &`, so only the `echo` was backgrounded and `sleep 20` ran in the foreground: the footer said `Kiro is working · 22s`.
- Run 2 (agent `echo-spike-c`, `bash -c 'sleep 20; echo finished > /tmp/kirospike-repo/bg2.txt'`, asked to end the turn with `started`): the tool line was `• Shell bash -c 'sleep 20; echo finished > /tmp/kirospike-repo/bg2.txt' &`, the result `Output:\n\n\nExit Code: 0`, the model said `started`, the turn ended after 5 s and the idle screen appeared. `bg2.txt` appeared 20 s later. For the next 30 s the screen stayed byte-identical: **no wake-up message, no new turn, no hook, no footer text about a background task** (`waiting.txt` is that idle screen, with a background command running; its footer is the normal `›  ask a question or describe a task ↵`). `messages.jsonl` had no entry after `turn_end`.
- Run 3: the same with `KIRO_FEATURE_BACKGROUND_EXECUTION_ENABLED=true KIRO_FEATURE_UNIVERSAL_BACKGROUND_TOOL_ENABLED=true` in the environment (flag names found in the bundled server): the same `… &` line, no wake-up. The bundled server has `terminal.background.*` code and a `background-process` tool inside the workflow feature, which was off; neither appeared in these sessions.
So Echo's Orchestrator cannot rely on a background shell. Options for later tasks: a foreground `echoctl wait` with the `timeout` parameter (up to 30 min, see below) and a loop; or the daemon types a message into the idle box when the awaited event arrives (the idle box accepts it, and a working box takes it as steering).

Longest foreground command:
- Default timeout **120000 ms**. `Call the shell tool once with command: sleep 130; echo done-130` (no `timeout`) ended after 2 min with:
```
    ╰ Output:
      Command timed out after 120000ms
      Exit Code: -1
```
  and the process was killed (no `sleep 130` left).
- The `timeout` parameter (milliseconds) raises it: `sleep 125; echo done-125` with `timeout=200000` returned `Output:\n done-125\n Exit Code: 0` after 2 m 10 s (the tool line shows `timeout=200000`).
- Maximum: **1800000 ms (30 minutes)**, from the bundled tool description (`Max: 1800000 (30 minutes). Commands exceeding timeout return partial output.`). Not run-tested; a 600 s `echoctl ask` fits, a one-hour `echoctl wait` does not and has to be re-issued. The description also says the host may set another default; the server reads a `terminal` setting with `commandTimeoutMs`, but `kiro-cli settings list` shows no such key, so it was not set.
- A command waiting in the foreground keeps the screen at the working state: `Kiro is working · 1m 48s · …`.

### Q9
**NOTE.** `env` inside the shell tool of a running session (`bash -c 'env | grep -iE "kiro|^HUB_|^TERM"'`) and in hook commands (`hook-env.txt`) shows these, among others (values are the ones seen; tokens omitted):
```
KIRO_SESSION_ID=sess_2508f79c-c2ff-4b6c-9014-9445f3d84360     (the running session; changes per session)
KIRO_VERSION=3.3.0   KIRO_VERSION_OVERRIDE=3.3.0   KIRO_LAUNCH_3_0=1   KIRO_AGENT_ENGINE=kas
KIRO_CHAT_CLI_BIN=/Users/me/.local/bin/kiro-cli   KIRO_CHAT_CLI_BIN_IDENTITY=unix:…   KIRO_CHAT_CLI_FALLBACK_BIN=…/kiro-cli/run/chat-cli-3.3.0
KIRO_KAS_NODE_PATH=…/kiro-cli/node   KIRO_KAS_SERVER_PATH=…/kiro-cli/kas/3.3.0-…/node_modules/@kiro/agent/dist/server/acp-server.js
KIRO_TUI_READY_FILE=/var/folders/…/kiro-tui-ready-<uuid>/ready   KIRO_TUI_READY_TOKEN=<uuid>   KIRO_TUI_FORCE_COLOR=3
KIRO_TURN_MARKER_DIR=…/kiro-cli/run/turn-markers
KIRO_TRUST_CLASSIFIER_MODE=enforce   KIRO_TRUST_CLASSIFIER_SHADOW=0   KIRO_TRUST_CLASSIFIER_SHADOW_LOG=
KIRO_TELEMETRY_CLIENT_ID=<uuid>   KIRO_TELEMETRY_ENABLED=true   KIRO_TELEMETRY_IS_ENTERPRISE=true   KIRO_TELEMETRY_OTLP_ENDPOINT=…
KIRO_CONTENT_COLLECTION_ENABLED=true   KIRO_CUSTOM_USER_AGENT=…   KIRO_FEED_FILE=…   KIRO_REMOTE_SESSIONS_ENDPOINT=https://app.kiro.dev
KIRO_ELEVATED_PRIVILEGES=none   KIRO_ENABLED_FEATURES=[]   KIRO_ROLLOUT_FEATURES=[]   KIRO_INFRA_SAFETY_ROLLOUT_ENABLED=0   KIRO_LITE_ROLLOUT_ENABLED=0   KIRO_VOICE_SUPPORTED=1
HUB_WORKER / HUB_AGENT: passed through unchanged (shell tool: `echo "W=$HUB_WORKER A=$HUB_AGENT S=$KIRO_SESSION_ID"` printed `W=w99 A=7 S=sess_f4f23efd-…`)
TERM=tmux-256color  TERM_PROGRAM=tmux
```
The ones that could confuse a nested Kiro started from a Kiro shell are `KIRO_SESSION_ID`, `KIRO_TUI_READY_FILE`, `KIRO_TUI_READY_TOKEN`, `KIRO_TURN_MARKER_DIR` and the `KIRO_CHAT_CLI_*` / `KIRO_KAS_*` paths. There is no variable named for "I am nested"; I did not start a nested Kiro to see whether it misbehaves. A hook or shell command that starts another `kiro-cli` should run it with `env -u KIRO_SESSION_ID -u KIRO_TUI_READY_FILE -u KIRO_TUI_READY_TOKEN`. The server also reads `KIRO_HOME` (moves all of `~/.kiro`), `KIRO_API_KEY`, `KIRO_LOG_LEVEL`, `KIRO_CHAT_LOG_FILE`, found by searching the bundle, not set here.
Echo's own variables (`HUB_WORKER`, `HUB_AGENT`) reach both the hook and the shell tool unchanged, so `echoctl` inside the agent finds its Worker.

### Q10
**NOTE.** `~/.kiro/sessions/<hash>/sess_<uuid>/messages.jsonl` is one JSON object per line: `{"id": …, "timestamp": …, "payload": {"type": …}}`. Types seen over every spike session:
| `payload.type` | meaning |
|---|---|
| `user` | the human's message |
| `assistant` | model text (`operationType: "Say"`) |
| `tool_call` | a tool call, with `toolName`, `args`, `status`, `kind` |
| `tool_result` | its result, `success` true or false |
| `turn_start` / `turn_end` | bracket a turn; `turn_end.stopReason` seen: `end_turn`, `error`, `cancelled` |
| `usage_summary` | credits per turn; `status`: `success`, `failed`, `aborted` |
| `session_event` | `category: "session_pause"` at each turn end |
| `session_metadata` | `key: "contextUsage"` (every turn) or `"displayError"` (a failed turn) |
| `session_start` | the agent's resolved prompt (`content`), `agentType`, `backgroundExecution` |
| `agent_note` | `<session_context>` block with the current model |
| `steering_inclusion` | steering documents added for a turn |
| `ContextualHookInvoked` | a hook ran: `name`, `hookActionType`, `status` |
| `pending_interaction` | a permission prompt opened |
| `interaction_resolved` | the answer to it |

One example of each (ids and uuids shortened, text redacted where it is the human's):
```
user                  {"type":"user","content":"What is the secret codeword? Reply with just the codeword.","documents":[],"images":[],"_meta":{"kiro":{"peerPromptGeneration":1,"userMessageTag":"prompt_3e7e…"}}}
assistant             {"type":"assistant","content":"PINEAPPLE-42","operationType":"Say","executionId":"d862…","turnId":"d862…","_meta":{"kiro":{"agentMode":"echo-spike-a"}}}
tool_call             {"type":"tool_call","toolCallId":"run_command_toolu_bdrk_01YH…","toolName":"execute_bash","args":{"command":"echo hi","description":"Print the word hi","run_in_background":false},"status":"completed","kind":"execute","executionId":"5bb7…","turnId":"5bb7…","actionType":"run_command","title":"Print the word hi"}
                      other tool: {"type":"tool_call","toolName":"fs_write","args":{"path":"/tmp/kirospike-repo/w2.txt","text":"ws2"},"status":"approved","kind":"edit","actionType":"create","title":"Write File","filePath":"/tmp/kirospike-repo/w2.txt"}
                      status values seen: completed, failed, denied, approved; kind: execute, edit, read; read tool name: read_file
tool_result           {"type":"tool_result","toolCallId":"run_command_toolu_bdrk_01YH…","content":"Output:\nhi\n\n\nExit Code: 0","success":true,"executionId":"5bb7…","turnId":"5bb7…"}
turn_start            {"type":"turn_start","executionId":"d862…","turnId":"d862…","boundarySource":"observed","userMessageTag":"prompt_3e7e…"}
turn_end              {"type":"turn_end","stopReason":"end_turn","executionId":"d862…","turnId":"d862…","boundarySource":"observed"}
usage_summary         {"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","unitPlural":"credits","usage":0.016251542288557214}],"elapsedTime":4082,"status":"success","executionId":"d862…","turnId":"d862…","requestIds":["5f20…"]}
session_event         {"type":"session_event","category":"session_pause","context":{"executionId":"d862…","turnId":"d862…","status":"success"}}
session_metadata      {"type":"session_metadata","key":"contextUsage","value":{"usagePercentage":1.4032},"executionId":"d862…"}
                      {"type":"session_metadata","key":"displayError","value":{"message":"The selected model is not available. Please select a different model and try again. (Request ID: 996c…)","errorType":"InvalidModelError","retryErrorType":"CLIENT_ERROR"},"executionId":"5db7…"}
session_start         {"type":"session_start","agentType":"echo-spike-a","backgroundExecution":false,"content":"You are a spike test agent. … <hook_output_channel>…"}
agent_note            {"type":"agent_note","content":"<session_context>\nOnly the last <session_context> block is current; it remains current until a later block supersedes it.\nThe current model is claude-haiku-5.5.\n</session_context>"}
steering_inclusion    {"type":"steering_inclusion","documents":["file:///Users/me/.kiro/steering/AGENTS.md","file:///Users/me/.kiro/steering/preferences.md"],"executionId":"d862…","turnId":"d862…"}
ContextualHookInvoked {"type":"ContextualHookInvoked","hookId":"echo-spike-a#hook-1","operationId":"82bc…","name":"spike-stop","hookActionType":"runCommand","status":"completed","executionId":"d862…","turnId":"d862…"}
pending_interaction   {"type":"pending_interaction","interactionType":"tool_approval","toolCallId":"run_command_toolu_bdrk_0167…","question":"touch y","options":[{"optionId":"accept","name":"Allow","kind":"allow_once"},{"optionId":"always-accept","name":"Always allow","kind":"allow_always"},{"optionId":"reject","name":"Deny","kind":"reject_once"},{"optionId":"always-reject","name":"Always deny","kind":"reject_always"}],"executionId":"35a9…","consentRound":1,"_meta":{"kiro":{"toolId":"run_command","command":"touch y","consent":{"capability":"shell","resource":"touch y","askType":"implicit","triggeringResource":"touch y","workspaceRoot":"/private/tmp/kirospike-repo"},"consentRound":1}}}
interaction_resolved  {"type":"interaction_resolved","toolCallId":"run_command_toolu_bdrk_0167…","outcome":"selected","selectedOption":"accept","executionId":"35a9…","consentRound":1}
```
Observations for milestone 2: `turn_start`/`turn_end` bracket a turn; the last entry before a turn ends is `usage_summary` plus `session_event`; a `pending_interaction` without a later `interaction_resolved` means the session is waiting on the human; `consent.capability` seen: `shell`, `fs_write`, `fs_read`; `askType` was `implicit` every time. `Esc` on a prompt leaves `outcome` other than `selected` (not captured separately).
The written `messages.jsonl` is the full history: a resumed session replays it. Entry timestamps are UTC ISO strings.

### Q11
**NOTE.** No way to read credits from the shell was found.
- `kiro-cli whoami` (and `--format json`): login only: `{"accountType":"IamIdentityCenter","startUrl":"https://….awsapps.com/start","region":"us-east-1","email":"<redacted>"}` plus the profile name and ARN. No credits.
- `kiro-cli settings list`: two keys (`chat.modelPicker.hiddenModels`, `chat.modelPicker.lastUsed`), no usage.
- `~/Library/Application Support/kiro-cli/data.sqlite3` `state` table: keys `api.codewhisperer.profile`, `auth.idc.*`, telemetry ids, versions. No usage; I did not read `auth_kv` (tokens).
- Headless `kiro-cli chat --no-interactive "/usage"` sends `/usage` to the model, which answers that it cannot see usage. It is not a command there.
- In the TUI, the slash command **`/usage`** ("Show plan usage and billing information") prints (`usage.txt`, taken from a real run):
```
 Estimated Usage | resets on 2026-12-01 | KIRO PRO+
 Credits (340.98 of 2000 covered in plan)
 ████████… 17.0%
 Overages
 Disabled
 Since your account is through your organization, for account management please contact your account administrator.
 esc to close                                                       Tab to switch to /context
```
  A reader of that screen gets used, total and reset date. `Esc` closes it.
- Every turn prints `▸ Credits: turn 0.01 • session 0.05 | Time: 7s` (a sum from this session only), and `messages.jsonl` `usage_summary.promptTurnSummaries[0].usage` holds the same per-turn number (0.0163 for the first turn). The footer's `◔ 1%` is context-window use, not credits; `session_metadata` `contextUsage.usagePercentage` has it as `1.4032`.
- The bundled server exposes an ACP method `_kiro/account/getUsage` (and calls the service operation `GetUsageLimits`), so `kiro-cli serve` or `kiro-cli acp` could answer it. Not run.

### Q12
**PASS.**
- `--model claude-haiku-5.5 --effort high --agent echo-spike-c` together start normally; the footer is `echo-spike-c · claude-haiku-5.5 · thinking · high · ◔ 1%` (`effort-high` run). The model list says efforts `low, medium, high, xhigh, max` are offered for this model.
- `--effort bogus` (headless) printed a warning and went on: `[warn] failed to set effort 'bogus': engine did not apply the requested level for model 'claude-haiku-5.5' (offers: low, medium, high, xhigh, max)`, exit 0.
- Unknown model, interactive: the TUI **starts** (the check is not before the TUI). A line appears: ``• Model `nonexistent-model-9` isn't available, so requests will fail. Choose another with /model.`` and the footer is `echo-spike-c · nonexistent-model-9 · ◔ 1%`. After the first prompt (`hi`) the turn ends with the line `• The model 'nonexistent-model-9' is not available. Please select a different model and try again. (Request ID: …)` (`unknown-model.txt`); no `Stop` hook; `messages.jsonl` gets a `displayError` (`InvalidModelError`) and `stopReason: "error"`.
- Unknown model, headless: after the request is sent, stderr/stdout `Error: The model 'nonexistent-model-9' is not available. Please select a different model and try again. (Request ID: …) (code -32000): {"errorType":"InvalidModelError","retryErrorType":"CLIENT_ERROR",…}`, **exit 1**.
So Echo must validate the model id itself (for example against `kiro-cli chat --list-models --format json`, whose entries have `model_id`, `rate_multiplier` and `context_window_tokens`) before it launches. Listed ids: `auto`, `claude-opus-5.5`, `claude-sonnet-5.5`, `claude-haiku-5.5` (0.06x), `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `grok-4.7`, `claude-opus-5`, `claude-sonnet-5`, `claude-opus-4.8`, `claude-opus-4.7`, `claude-opus-4.6`, `claude-sonnet-4.6`, `claude-opus-4.5`, `claude-sonnet-4.5`, `claude-haiku-4.5`, `deepseek-3.2`, `minimax-m2.5`, `minimax-m2.1`, `glm-5`, `qwen3-coder-next`; `default_model: "auto"`.

### Q13
**PASS.** Folders outside the workspace.
- With the rule (agent `echo-spike-d`: `fs_read` and `fs_write` `allow` for `/tmp/kirospike-outside/**`): `Use the write tool to create the file /tmp/kirospike-outside/y.txt with the content hello2.` wrote it with **no prompt** (`• Write file:///tmp/kirospike-outside/y.txt`, `    added 1 line in y.txt`); the file holds `hello2`. `Use the read tool to read /tmp/kirospike-outside/x.txt` returned `1  hello` with no prompt.
- Without a rule (agent `echo-spike-a`, no `fs_*` rules): the same kind of write asked (`permission-fswrite.txt`): `Write File requires approval`, `fs_write → /private/tmp/kirospike-outside/x.txt`. The model itself had said it was "fine" because the user named the path, but the permission system still asked.
- A different outside folder than the one in the rule (`/tmp/kirospike-other/z.txt`, agent `d`) still asked. A write inside the workspace with only the outside rules (`/tmp/kirospike-repo/w1.txt`, agent `d`) also asked, showing `fs_write → w1.txt`.
- The write tool took `path` with `/tmp/…`, shown as `file:///tmp/…` once done; the permission resource is the symlink-resolved `/private/tmp/…`, and a rule written as `/tmp/…` still matched it.

## Extra notes

- **Hook commands** run through a shell (an `A=b cmd` prefix works), with the session's cwd as working directory (`pwd` in the stub printed `/tmp/kirospike-repo`) and the environment of Q9 (all `KIRO_*` variables plus the parent's).
- **Trust, agent files and `agent list`**: `kiro-cli agent list` in `/tmp/kirospike-repo` printed `Workspace: /private/tmp/kirospike-repo/.kiro/agents` and `Global: ~/.kiro/agents` and listed only the built-ins `kiro_default`, `kiro_help`, `kiro_planner`, even with Markdown agents present in both; `--agent` still loaded them, so `agent list` cannot be used to check a generated file. `kiro-cli agent validate --path <file>.md` fails with `invalid number at line 1 column 2` (it parses JSON only), so it cannot check the Markdown form. The loader log is `~/.kiro/logs/<stamp>-<pid>/kiro.log` (`[KiroAgent] Using custom agent profile: echo-spike-a`, `[ProfileLoader] profile.loaded {"agentId":"echo-spike-a"}`).
- Kiro itself created `~/.kiro/agents/agent_config.json.example` at 16:28 on the first launch (not by the spike's file writes).
- All sessions the spike created remain under `~/.kiro/sessions/a44897a43362370a/` (about 28 directories), as instructed.
- The human's own `kiro-cli` (pid 86154 on ttys026, started 12 Nov 13:51, version 3.3.0 servers) was running throughout; its session lease `sess_96fafafe-….lease` is still there. It was not touched, and it is not a `kiro-cli chat` process.
- The footer text at the left of the input box, idle: `ask a question or describe a task ↵`; right of it on the next row: `/sessions to resume · /copy to clipboard`. Working: `Kiro is working · <N>s · Type to steer · Ctrl+S to queue`.
- First-start extras seen in `idle.txt`: the line `▸ What's new   ctrl+o to expand` (collapsed) and, after the first turn, `▸ What's new` without the hint. Neither is a state signal.
- Tips such as `  ╰ Tip: Type /tools to see all available tools Kiro can use in the current session.` appear under the spinner at random; a reader must not treat them as chat text.

## Complete working agent file

Everything in this file was loaded and exercised (hooks in `echo-spike-z`, rules in `echo-spike-a` to `echo-spike-g`). Front matter keys that loaded: `name`, `description`, `model`, `tools`, `permissions.rules[]` (`capability`, `match`, `effect`), `hooks[]` (`name`, `trigger`, `matcher`, `action.type`, `action.command`). The inline `{type: command, command: "…"}` form of `action` also loaded.

```markdown
---
name: echo-spike-z
description: "Echo worker: generated agent file"
model: claude-haiku-5.5
tools: ["read", "write", "shell"]
permissions:
  rules:
    - capability: fs_read
      match: ["/tmp/kirospike-repo/**", "/tmp/kirospike-outside/**"]
      effect: allow
    - capability: fs_write
      match: ["/tmp/kirospike-repo/**", "/tmp/kirospike-outside/**"]
      effect: allow
    - capability: shell
      match: ["echo *", "ls *", "git status *"]
      effect: allow
    - capability: shell
      match: ["rm -rf *", "git push *"]
      effect: deny
hooks:
  - name: echo-session-start
    trigger: SessionStart
    action:
      type: command
      command: HUB_WORKER=w42 HUB_AGENT=3 /tmp/kirospike/hook.sh SessionStart
  - name: echo-stop
    trigger: Stop
    action:
      type: command
      command: HUB_WORKER=w42 HUB_AGENT=3 /tmp/kirospike/hook.sh Stop
  - name: echo-pre-shell
    trigger: PreToolUse
    matcher: shell
    action:
      type: command
      command: /tmp/kirospike/hook.sh PreToolUse
---

You are Worker w42. The codeword is PINEAPPLE-42.
Answer in one short line.
```
This exact text was saved as an agent file and run once more (`kiro-cli chat --v3 --no-interactive --trust-workspace --agent echo-spike-z --model claude-haiku-5.5 'Run exactly this shell command: echo proof'` with `HUB_WORKER` unset): the answer was `The command printed \`proof\` and exited with code 0.`, and `SessionStart`, `PreToolUse` and `Stop` all fired, each with `HUB_WORKER=w42` and `HUB_AGENT=3` in its environment.

The stub `/tmp/kirospike/hook.sh` read stdin, took `hook_event_name` from it, wrote it to `/tmp/kirospike/hook-<event>.json`, appended it to `hook-all.log` and appended `env | grep -E '^(HUB_|KIRO|ECHO_)'` to `hook-env.txt`.

Command lines that worked, for the adapter:
```
kiro-cli chat --v3 --agent <name> --model <id> [--effort high] --trust-workspace            # interactive TUI, idle box
kiro-cli chat --v3 --agent <name> --model <id> --trust-workspace 'first message'            # starts the turn itself (not if it starts with -)
kiro-cli chat --v3 --resume-id sess_<uuid> --model <id> --trust-workspace                   # resume, agent restored
kiro-cli chat --v3 --no-interactive --trust-workspace --agent <name> --model <id> '<msg>'   # headless, prints the answer, exit 0
kiro-cli chat --list-sessions --format json                                                 # sessions of the cwd
kiro-cli chat --list-models --format json                                                   # model ids
```

## Fixtures

`crates/hub/tests/fixtures/kiro/`: `idle.txt`, `working.txt`, `working-shell.txt`, `working-text.txt`, `done.txt`, `permission.txt` (shell), `permission-fsread.txt`, `permission-fswrite.txt`, `permission-always.txt`, `allowed-once.txt`, `rejected.txt`, `denied-by-rule.txt`, `cancelled.txt`, `cancelled-tool.txt`, `trust.txt`, `waiting.txt`, `usage.txt`, `unknown-model.txt`, `resumed.txt`, `hook-SessionStart.json`, `hook-UserPromptSubmit.json`, `hook-PreToolUse.json`, `hook-PostToolUse.json`, `hook-Stop.json`, `hook-SessionEnd.json`.

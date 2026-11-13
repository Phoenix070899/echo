# Kiro runs as a third agent CLI, with its prompt in a generated agent file and its session id from a hook

Decided: 2026-11-13
Status: accepted

Supersedes: features/0036's "only `claude` runs today" and features/0037's "claude and codex", where they say which CLIs run; the rest of both stands.
`cli: kiro` (a Profile, `settings.json`, the CLI picker in Settings, or `echoctl worker start --cli kiro`) runs the `kiro-cli` binary on its V3 harness, so the human's Kiro credits pay for the Claude, GPT and other models Kiro offers.
Models are Kiro's own ids, like `claude-sonnet-5.5` (a dot, not a dash); a bare id or `kiro/<id>` is accepted, and another provider's `provider/model` is refused with a message naming it.
Kiro has no flag for a system prompt, extra folders, or a session id, so the adapter writes an agent file for each distinct start under `~/.kiro/agents/` named `echo-<hash of its content>.md` and starts `kiro-cli chat --v3 --agent <that name>`. The file holds the model, the tools, the folders it may read and write, the permission rules, the hooks, and the prompt as its body.
A content-named file is never rewritten with other content, so two starts at once cannot read each other's prompt; the files are small and stay.
Kiro sets its own session id, so the file's SessionStart hook runs `echoctl notify`, which records the id on the Worker or agent as it does for Codex; a resume is `kiro-cli chat --resume-id <id>`, and a session exists when `~/.kiro/sessions/*/<id>/` does (under `$KIRO_HOME` when set).
`--trust-workspace` answers the folder-trust dialog, so no keys are sent for it. A Worker's permission rules allow its work in the checkout and deny the destructive commands `settings/worker.json` asks about for Claude; whatever else still prompts is read from the screen and approved or denied as for the other CLIs.
Which CLI and model an agent runs with is picked in the four levels of features/0036, unchanged.
Chat, the usage bar, stats, the Orchestrator's view in `mod/`, Orchestrator renewal by context size, and session titles stay Claude Code's for now, and show as unsupported or not counted for Kiro until a later decision brings them.
Why: the human's Claude usage ran out, and Kiro offers the same models on other credits, so work can go on in Echo instead of in a bare terminal.
Rejected: driving Kiro over its Agent Client Protocol server (`kiro-cli acp`), which would replace Echo's terminal-and-screen design for one CLI; `KIRO_HOME` pointed at an Echo folder to hold the agent files, which also moves the human's sign-in and sessions.

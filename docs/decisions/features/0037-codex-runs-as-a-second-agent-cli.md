# Codex runs as a second agent CLI, with its hooks inline and its prompts read from the screen

Decided: 2026-10-28
Status: accepted

Supersedes: features/0036's "only `claude` runs today"; the rest of 0036 stands.
`cli: codex` (a Profile, a settings file, or `echoctl worker start --cli codex`) runs OpenAI's Codex CLI with `openai/<model>` or a bare model name; another provider's model is refused.
Codex sets its own session id, so the daemon passes a SessionStart hook that runs `echoctl notify`, records that id on the Worker or agent, and resumes with `codex resume <id>`; for an Orchestrator it is recorded once its first turn starts.
Echo's hooks and prompt go inline as `-c` settings (`hooks.SessionStart`, `hooks.Stop`, `developer_instructions`, `model_reasoning_effort`) with `--dangerously-bypass-hook-trust`, since Codex would otherwise skip them as unreviewed; that flag also runs the human's own unreviewed Codex hooks for that session.
A Worker runs with `-a on-request -s workspace-write` and network on, so it asks only to leave its checkout; the human's own Codex reviewer setting still applies.
Permission prompts, the trust dialog, a turn under way, and background terminals are read from Codex's screen (`screen::codex_look`), and approved with Enter or denied with Esc, as for claude.
The Stop hook reports a turn that ended without `echoctl done` as an idle blocker.
Claude-only extras stay so for Codex: the Orchestrator's view in `mod/`, the `echoctl:echo` skill, a Profile's `tools` list, session titles, and the account usage.
Why: the human wanted GPT models through Codex before opencode.
Rejected: the PermissionRequest hook, which fires before Codex's own reviewer approves most requests, so it reported prompts nobody saw (bugs/0052); trusting the folder with `-c projects.<path>.trust_level`, which Codex ignores for its dialog.

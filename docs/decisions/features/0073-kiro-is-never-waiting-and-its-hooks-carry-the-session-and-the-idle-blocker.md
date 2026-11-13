# Kiro is never "Waiting" on screen; its hooks carry the session id and the idle blocker

Decided: 2026-11-13
Status: accepted

`screen::kiro_look` never returns `Look::Waiting`, because Kiro's screen has no footer for background work. A screen with no input box is `Working`, and Echo types nothing into it.
The agent file subscribes to `SessionStart` (the first prompt, which records the session id) and, for a Worker, to `Stop`, which `echoctl notify` reports as an idle blocker ("Its turn ended with no Final Report.") as it does for Codex.
`echoctl notify` ignores any other Kiro event (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SessionEnd`) and prints nothing, so a hook added later cannot spam the Orchestrator.
Permission prompts and the trust dialog are still read from the screen.
Why: Kiro runs no background work Echo could see, so the state is Working, Idle or a prompt; the hooks give what the screen cannot, the id and the end of a turn.

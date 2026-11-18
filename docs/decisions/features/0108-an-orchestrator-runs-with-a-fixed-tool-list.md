# An Orchestrator runs with a fixed tool list

Decided: 2026-11-18
Status: accepted

Supersedes: features/0033 for Orchestrators only: they no longer load the skills-only plugin in `skills/`, because they no longer have the `Skill` tool; Normal sessions still load it.
An Orchestrator's Claude Code starts with `--tools Bash,Read,Write,Edit,ToolSearch` (`ORCHESTRATOR_TOOLS` in `crates/hub/src/launch.rs`), and its plugins are only `mod/`.
Write and Edit are for Task specs under `$ECHO_REPO/.tasks/`; every other change still goes through a Worker.
`ToolSearch` stays so MCP tools load on demand instead of in full.
`orchestrator.md` points at `skills/skills/echo/SKILL.md` for `echoctl ui`, to be read once when first needed.
Why: measured on one-word prompts, the full Claude Code tool set and the `Skill` tool, which lists every skill the human has, made up half of the Orchestrator's start context (39k tokens down to 19k), re-read on every request; the Orchestrator's rules already send searching, research and edits to Workers.
Rejected: keeping `Skill` for the one `echo` skill (about 7k more tokens per request); dropping the human's user-level settings too, which would also drop their permission rules.

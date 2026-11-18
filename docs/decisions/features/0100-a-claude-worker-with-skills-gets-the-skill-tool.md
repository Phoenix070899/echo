# A Claude Code Worker whose Profile names skills gets the Skill tool

Decided: 2026-11-16
Status: accepted

Builds on features/0099.
When a Worker runs on Claude Code with a tools list, and its Profile (or Member) names at least one skill, Echo adds `Skill` to the list it passes as `--tools`, as it already adds `ToolSearch`.
A Profile without skills, and one with no tools list, start as before; Codex and Kiro are left alone.
The human does not have to add `Skill` to Tools by hand.
Why: `--tools` limits the Worker to the tools named, and Claude Code runs every skill through the Skill tool, so no Worker could use the skills its Profile names.
Rejected: adding `Skill` to every Worker, which would widen Profiles that name no skills; asking the human to add it, which fails silently when they forget.

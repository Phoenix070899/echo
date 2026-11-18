# Workers could not use any skill their Profile names

Found: 2026-11-16
Where: crates/hub/src/profile.rs (start, tools), crates/hub/src/cli.rs (claude)

A Worker started from `hinata` (`skills: graft`) or `naruto` (`skills: tdd`) was told to use the skill, but could not load it.
Cause: a Claude Code Worker starts with `--tools` set to its Profile's tools (`Read, Grep, Glob, Bash`), which leaves out the Skill tool every skill runs through.
Found by running `claude -p` with a Worker's tools and skills line: without `Skill` it reported no Skill tool, with it both `graft` and `tdd` (as `mattpocock-skills:tdd`) loaded.
Fix: a Claude Code Worker whose Profile names skills gets `Skill` added to its tools (features/0100).
Lesson: when a setting tells an agent to use something, check the agent can reach it with the tools it actually starts with.

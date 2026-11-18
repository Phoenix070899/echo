# Claude's model list has Fable 5.2 first

Decided: 2026-11-16
Status: accepted

Supersedes: features/0091's "its picker's three (Opus, Sonnet, Haiku 5.5) are written in `models.rs`".
The Claude models written in `models.rs` are Fable 5.2 (`anthropic/claude-fable-5-2`), then Opus, Sonnet and Haiku 5.5; the ones the account's `.claude.json` caches still come before them.
Claude Code runs `claude-fable-5-2` (checked 2026-11-16: `claude -p --model claude-fable-5-2` answered on it) though it warns that it does not recognize the name, and its picker does not list it.
Why: the human wants Fable 5.2 in every Claude model picker.
Rejected: waiting for the account's cache to list it, which it does not yet.

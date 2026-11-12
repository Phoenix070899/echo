# `chat.read` pages backward by byte offset and `chat.commands` lists the slashes

Decided: 2026-11-12
Status: accepted

`chat.read` with `before` and `page_session` returns the page of items ending at that byte of that session's transcript, with the `start` of the page and whether `more` is left; at a session's start it continues in the session before, ending with a renewal divider.
`chat.commands` returns Claude Code's own commands (without `/clear` and `/resume`, which move the agent to another session), the skills the transcript lists, and the command files in `~/.claude/commands` and the repo's `.claude/commands`, each with whether it opens a menu.
Why: Echo never reads transcripts itself (ADR 0010), so paging and completion come from the daemon and the phone gets them too.

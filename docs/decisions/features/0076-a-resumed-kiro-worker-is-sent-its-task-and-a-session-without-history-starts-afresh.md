# A resumed Kiro Worker is sent its Task, and a Kiro session with no history starts afresh

Decided: 2026-11-13
Status: accepted

Supersedes: features/0068's "a resume is `kiro-cli chat --resume-id <id>`", only for a session that holds no turn yet; the rest of 0068 stands.
The first message of a resumed Kiro Worker is `RESUMED` (the lead line), a blank line, `Your Task:`, a blank line, and the Worker's Task from the database, cut at 4000 characters with `[Task cut at 4000 characters.]` after it. Claude's and Codex's resume message is `RESUMED` alone, as before.
`--resume-id` is passed only when a folder for the id under `$KIRO_HOME/sessions/*/` holds a `messages.jsonl`; without one the agent starts a new session on the same agent file, model and message, and its SessionStart hook records the new id. A folder alone is not enough: Kiro makes it at the TUI's start, before any prompt.
The text sent is stored as the Worker's Echo input, so the chat can tell it from the human's words.
Why: Kiro opens a plain session on its default agent and model when `--resume-id` names an id it has no history for (docs/bugs/0070), and that session had no Task; the Task in the message covers that case and any other where the history is missing.
Rejected: only adding the Task to the message, which leaves such a Worker on Kiro's default agent and model, without the Worker Contract; only starting afresh, which leaves a model that replays a long history with a lead line and no restated instruction.

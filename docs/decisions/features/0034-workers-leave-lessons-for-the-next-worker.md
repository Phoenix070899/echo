# Workers leave Lessons for the next Worker, and Preferences leave the echo repo

Decided: 2026-10-28
Status: accepted

`echoctl done --lesson "<one line>"`, repeatable, adds a dated, signed bullet to the repo's Lessons, `memory/repos/<folder>-<hash>/lessons.md` in the daemon's state.
Every new Worker and Orchestrator in that repo gets the Lessons in its prompt, after the Preferences; Lessons are saved without asking the human, and the Final Report lists them so the Orchestrator names them in its Summary.
Past 60 Lessons the Final Report asks the Orchestrator to have an `ino` Worker merge them; `ino` also drops Lessons the human says are wrong.
The human's Preferences move from the echo repo's `memory/preferences.md` to `memory/preferences.md` in the state folder, copied once; the echo repo keeps an empty template, so nobody's rules ship with Echo.
Agents get `--add-dir` on the state's `memory/` folder only, so `ino` edits these files without a prompt and nothing else of the daemon's state is theirs.
Both are plain Markdown put into the prompt, so any agent CLI can use them, not only Claude Code.
Why: Workers started fresh each Task and paid again for what an earlier Worker had found out, and Echo is to be used by people other than its author.
Rejected: keeping Lessons in `hub.db`, which only Echo could read or edit; writing them into the repo, which would put Echo's files in every repo's git.

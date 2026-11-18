# Lessons grew past 100 KB while staying under the 60-Lesson limit

Found: 2026-11-18
Where: crates/hub/src/lessons.rs (`LIMIT`, `add`), crates/hub/src/daemon.rs (the Final Report's merge note), profiles/ino.md

The lanh-ai Lessons file reached 110 KB in 35 bullets, and every Worker and Orchestrator in that repo carried all of it in its prompt: about 27k tokens on every turn, more than half of a Worker's start context.
Cause: the limit counted bullets only, and `ino` merged Lessons by joining different facts into one line, so the count stayed under 60 while single bullets grew to 10 KB.
Fix: a Lessons file is also over its limit past 16,000 characters (`SIZE_LIMIT`), and the Final Report then asks for a merge that shortens it; `ino` keeps each Lesson one fact under about 300 characters and the file under 16,000 characters.
Lesson: a limit on text that goes into every prompt measures its size, not the number of items in it.

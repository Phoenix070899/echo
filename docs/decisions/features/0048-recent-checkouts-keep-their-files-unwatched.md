# The last few checkouts keep what they read, unwatched, so the Files column never shows empty

Decided: 2026-11-02
Status: accepted

Supersedes: features/0025's "lets it go" and "Keeping recent checkouts warm was rejected", for what a checkout read, not for its watcher.
Showing a checkout still stops every other checkout's watcher, as features/0025 has it.
The 4 checkouts shown last keep the files, marks, and branch they read; showing one again shows those at once and reads it again with git, and the fresh read replaces them.
Why: coming back to a checkout showed an empty Files column until git answered, which the human sees on every switch between worktrees; Orca keeps each worktree's git status for the same reason.
It costs about 4 ms more main-thread time a switch with the Files column shown (46.2 against 41.8 ms, `FILES=1 app/scripts/measure-switch.sh`), as bugs/0055 found; the empty column was judged worse.

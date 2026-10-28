# Profiles come from Echo, from you, and from the repo, and Echo's own carry no one's taste

Decided: 2026-10-28
Status: accepted

A Profile is found in three folders, each replacing a same-named file in the one before: Echo's own `profiles/`, yours in `profiles/` in the daemon's state (`~/.echo`), and the repo's `.echo/profiles/` in its main checkout, shared through its git.
A replacing file replaces the whole Profile, never single fields, so one file always shows what a Worker starts with.
`echoctl profile list` shows every Profile and where it comes from, and a file that does not load with why; `copy <name> [--repo]` makes the editable copy, and `new <name> [--repo]` a blank one.
The Orchestrator picks Profiles from `echoctl profile list`, and Echo's Fan Out lists the repo's too.
The Worker Contract is always put before a Profile's role, so no Profile can change how Workers report.
Echo's own Profiles name no skill or tool only their author has; the author's versions, with `graft` and `tdd`, moved to their own `profiles/`.
Why: the human wants Echo used by many people, each with their own taste, and teams to share Profiles in a repo.
Rejected: merging fields across levels, which hides where a setting comes from; editing Echo's own `profiles/`, which every Echo update would undo.

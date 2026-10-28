# Settings sets each repo's worktree setup and the files new worktrees copy

Decided: 2026-10-28
Status: accepted

Settings has a Worktrees section, after Agents: a repo picked from a menu, its setup command, and the ignored files to copy, one per line (features/0039).
They are written to that repo's `.echo/settings.json` on Save, with Revert until then, so a team can commit and share them; Echo keeps no copy of its own.
A change is checked before it is written: a path outside the repo is refused and the file stays as it was; an empty setup removes it.
`echoctl ui settings worktrees` shows this section.
Why: the human wanted the install command set per repo in Settings, not in a file by hand.

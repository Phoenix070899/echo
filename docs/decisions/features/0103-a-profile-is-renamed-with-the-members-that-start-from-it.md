# A Profile is renamed, and the Members that start from it follow

Decided: 2026-11-16
Status: accepted

Builds on features/0096 and features/0098.
`profile.rename` (and `echoctl profile rename <name> <to> [--repo]`) renames your or the repo's file of a Profile, with the `name` in its front matter.
Every Member of your Teams and the repo's Teams that starts from the old name is moved onto the new one, and those Teams are written again.
It is refused when the new name is taken at any level, and while one of Echo's own Teams starts from the old name and no other level has that name, since Echo's Teams are never written.
When another level has the old name (your copy of Echo's `naruto`), Echo's own Teams keep starting from that one.
Echo's own Profiles are not renamed; Duplicate makes a copy under a new name.
A repo's Team in another checkout is not seen, so its Members keep the old name.
Why: the human wants to rename a Profile in one step instead of duplicating, repointing Members, and deleting.
Rejected: leaving Members on the old name, which breaks every Team that uses it.

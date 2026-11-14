# A Team has Members, each started from a Profile for an Action

Decided: 2026-11-14
Status: accepted

A Team file gains `members`, a flat array in tree order; a Member is one Worker slot of the Team: a name, an Action, the Profile it starts from, and the changes this Team makes to that Profile.
A Member's fields are `id`, `action`, `profile`, `parent`, `instructions`, `replaceRole`, `cli`, `model`, `effort`, `tools`, `skills`, `context`, `lessons`, `writes` and `worktree`, all camelCase.
Only `id`, `action` and `profile` are required; `parent` is another Member's `id` and is absent at level 1; `worktree` is `"current"` or `"new"` and is only a hint printed to the Orchestrator; a field a Member leaves out means the level below.
The tree is flat in the file, with `parent` naming the Member above, so that a move is a small diff in git and a merge conflict stays readable.
A Member's `id` follows `profile::valid_name` (lowercase letters, digits and `-`, at most 32 characters, not starting with `-`), and ids are unique in a Team.
A Team is refused, when it is saved and again when it is used, if a `parent` names no Member of the Team, if the parents form a cycle, if the tree is deeper than 3 (level 1 is depth 1), if a `verify` Member's parent is not an `execute` Member, if an `action` is neither one of Echo's Actions (features/0087) nor `custom`, if it holds more than 24 Members, or if a Member's `cli`, `model` and `effort` are a pair that cannot run (checked as for the Team's other picks, under the label `members.<id>`).
A Member's `profile` must name a Profile that exists; the daemon checks that when the Team is saved and used, not the file format.
`echoctl worker start <name>` looks the name up as a Member `id` first; else as the `profile` of the first Member in tree order; else as a bare Profile, as before.
When a Worker starts from a Member, the Member is laid over the Profile: `instructions` are added after the Profile's role, or replace the role when `replaceRole` is true; `tools`, `skills` and `context` replace the Profile's list when the Member's list is not empty; `lessons: false` leaves the Lessons out of that Worker's prompt (the default is true, as today); `writes` is for the reader and the Orchestrator's prompt only.
A Worker whose Member is gone from an edited Team, on a resume or in the ledger's rows, falls back to the Profile-level choices of the `profile` stored with it and never errors for that.
A Team without `members` behaves exactly as before, and `workers.profiles.<Profile>` (features/0081) is still read and still works beside Members.
Why: the human wants two differently set Workers of one Profile in one Team, each with its own instruction, model, tools and context, without editing the shared Profile file that every Team reads.
Rejected: nesting the Members as JSON, which makes a move rewrite many lines; a Member that replaces its Profile whole, which would copy the role text into every Team; making Members a new kind of Profile file, which leaves the Team without the picture of its Workers; treating a Member whose Profile is missing as a warning, which would start a Worker with no role.

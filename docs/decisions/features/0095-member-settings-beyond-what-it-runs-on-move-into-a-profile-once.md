# A Member's settings beyond what it runs on move into a Profile of its own, once

Decided: 2026-11-15
Status: accepted

When the daemon reads a Team whose Member sets any of `instructions`, `replaceRole`, `tools`, `skills`, `context`, `lessons`, `writes` or `worktree`, it writes a Profile `<team>-<member>` at the Team's level: the Member's Profile with those fields laid over it as features/0084 laid them, and the Member then starts from it.
A `workers.profiles.<Profile>` entry moves onto each Member of that Profile that sets none of the three fields itself.
The Team file is written again without the moved fields, and the daemon logs what it moved; a Team at Echo's level is never written, since Echo's own Teams set none of them.
A Profile gains `worktree` (`current` or `new`), the hint a Member used to carry.
Why: nothing about how an existing Worker runs may change silently when the fields leave the Member (features/0094).
Rejected: ignoring the old fields, which changes Workers without a word; refusing the Team until the human fixes it, which stops their Orchestrators for a file format change.

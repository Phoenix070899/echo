# A Profile that a Team's node starts from cannot be deleted

Decided: 2026-11-15
Status: accepted

Deleting a Profile is refused while a Member of any Team the repo can use names it, and the refusal names those Teams and Members.
Deleting your or the repo's copy of one of Echo's Profile names is allowed: Echo's own Profile is what the Members start from again.
A Profile has no rename; Duplicate it under the new name, point the Members at it, then delete the old one.
Why: a Member whose Profile is gone starts no Worker (features/0084), and a Profile's name is how every Team refers to it.
Rejected: renaming that rewrites every Team, which edits Team files the human did not open, some of them shared through a repo's git.

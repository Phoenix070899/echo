# A Profile's file is deleted freely while another level still has its name

Decided: 2026-11-15
Status: accepted

Builds on features/0096.
Deleting your or the repo's file of a Profile is refused only when no other level (Echo's, yours or the repo's) has a file of that name and a Member of a Team the repo can use names it.
When another level has the name, that level's Profile is what the Members start from again, as with Echo's own (features/0096), so the delete goes ahead.
`profile.delete` and `echoctl profile delete <name> [--repo]` follow this; `profile.reset` stays as it was.
Why: the refusal exists so no Member is left without a Profile, and a file shadowing another level's never leaves one.
Rejected: allowing it only over Echo's own names, which refuses deleting the repo's copy of one of your Profiles for no reason.

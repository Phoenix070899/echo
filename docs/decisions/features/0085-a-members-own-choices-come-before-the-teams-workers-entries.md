# A Member's own choices come before the Team's Workers entries

Decided: 2026-11-14
Status: accepted

This extends the order of features/0081 for a Worker; it supersedes nothing.
A Worker's CLI, model and effort come from the first of these that sets the field: what was picked for it (`echoctl worker start --cli --model`), its Member, its Team's `workers.profiles.<Profile>`, its Team's `workers`, the Profile, the repo's `.echo/settings.json`, then the daemon's state `settings.json`.
A Member therefore takes the place that `workers.profiles.<Profile>` had in features/0081, above it, and a Worker that starts from no Member follows the order of features/0081 unchanged.
`forceCli` (features/0075) treats a Member like any other entry of the Team: a field the Team names, a Member included, wins over `forceCli`, and a field the Team does not name is forced as before.
Orchestrators are not affected; their order stays the one of features/0081.
`echoctl profile list` and the Settings section show what a Member runs with after this order and `forceCli`.
Why: a Member is the most specific thing the human can say about one Worker, and it has to win over the Team's setting for all Workers and for all Workers of its Profile, or editing it would sometimes do nothing.
Rejected: putting the Member below `workers.profiles`, which would make an old entry hide a new and more specific one; letting `forceCli` win over a Member, which would undo what the human named in the Team, and features/0081 already chose the Team over `forceCli`.

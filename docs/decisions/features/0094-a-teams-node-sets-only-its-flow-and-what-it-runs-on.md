# A Team's node sets only its place in the flow and the CLI, model and effort it runs on

Decided: 2026-11-15
Status: accepted

Supersedes: features/0084's Member fields `instructions`, `replaceRole`, `tools`, `skills`, `context`, `lessons`, `writes` and `worktree`, and its overlay of them on the Profile; features/0081's and 0085's `workers.profiles`. Everything else in them stands.
A Member holds `id`, `action`, `profile`, `after`, `x`, `y`, and `cli`, `model` and `effort`; everything else about a Worker is its Profile's, edited in the Profiles section (ui-ux/0145).
A Team keeps the Orchestrator's setup and rules, and `workers` as one default `cli`, `model` and `effort` for every node that does not set its own; `workers.profiles` is gone.
A Worker's CLI, model and effort come from the first of these that sets the field: what was picked when it started, its Member, its Team's `workers`, its Profile, the repo's `.echo/settings.json`, then the daemon's state `settings.json`; `forceCli` (features/0075) is forced only where the Team names nothing, as before.
Why: the human wants a Team to say which Workers exist, how they hand off and when they run, and one place for what a Worker is; the CLI, model and effort stay on the node so one Team can run a Profile on another CLI or model without a second Profile.
Rejected: moving the CLI, model and effort into Profiles too, which makes a Kiro Team copy every Profile; setting them per Profile within a Team, which cannot give two nodes of one Profile different models.

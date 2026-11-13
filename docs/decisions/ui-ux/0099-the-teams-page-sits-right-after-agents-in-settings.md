# The Teams page sits right after Agents in Settings

Decided: 2026-11-13
Status: accepted

Settings lists Teams as its own page directly under Agents, before Worktrees. The page is a list of the Teams the selected repo can use, each row 30 pt at least with its origin (shipped, user or repo) in grey beside the name and its problem, if it has one, in orange under it; the picked row sits on the selected fill. New Team, Duplicate and Delete sit under the list, and Delete shows only for a user or repo Team. The editor follows on the same page: description, Orchestrator, Workers, the Profiles set apart, Rules, Instructions, and Save with Revert.
The Teams are read fresh each time the page opens, for the repo selected in the window, so that repo's own Teams are listed with them.
A rule the Team leaves out shows the human's Orchestrator setting in its toggle, and the Team only holds a rule once it has been changed there; "Use my settings" puts all four back to unset.
The daemon's message for a Team it refuses is shown under the fields, as the daemon wrote it; Echo checks only that the Team has a name.
Why: a Team is the setup of the Orchestrator and its Workers, which Agents already configures one setting at a time, so the two pages belong side by side; a page of its own keeps the Agents page from growing a second list.
Rejected: a section inside the Agents page, which already holds the default CLI, the Profiles and the Orchestrator rules; a sheet from the New session sheet, which would hide the Teams from the human who only wants to edit one; checking models and efforts in Swift, which would drift from the daemon's rules.

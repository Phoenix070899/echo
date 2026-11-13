# A Team is a named setup for an Orchestrator, its Workers and its rules, picked when a session starts

Decided: 2026-11-13
Status: accepted

A Team is a JSON file `<name>.json` in `teams/` at three levels, a later level replacing a same-named file whole, as Profiles do: the echo repo's `teams/` (shipped), `~/.echo/teams/` (the human's), and `<repo>/.echo/teams/` (one repo's).
It holds: `description`; `orchestrator` (`cli`, `model`, `effort`, `rotateAt` in tokens); `workers` (`cli`, `model`, `effort` for every Worker, and `profiles`, a map from a Profile's name to its own `cli`, `model` and `effort`); `rules` (`maxWorkers`, `planApproval`, `review`, `mergeWithoutAsking`); and `instructions`, text added to the end of the Orchestrator's prompt. Every field is optional; a missing one means the level below.
An Orchestrator is started with a Team (`agent.open` takes `team`; the New session sheet has a picker; the choice is kept on the agent as `agents.team`), and its Workers follow the Team of the Orchestrator that started them. A Normal session and a Terminal have no Team.
For an Orchestrator the order is, from the highest: what was picked for that agent, its Team's `orchestrator`, then the order of features/0053 and 0036 as before. For a Worker: what was picked for it, its Team's `workers.profiles.<Profile>`, its Team's `workers`, then the Profile's own and the levels below, as features/0036 orders them. A Team's `workers` therefore wins over a Profile's own `cli`, `model` and `effort`, the way `forceCli` (features/0075) does for everyone; `forceCli` stays for agents that have no Team and for the Workers a Team does not name.
The Team's `rules` and `rotateAt` replace the human's same-named settings for that Orchestrator, and `instructions` is added after the rules; Lessons, Preferences and the repo line are added as now.
A Team is read when its Orchestrator starts or resumes and when a Worker starts or resumes, so editing one changes running sessions only at their next start or resume.
A pair that cannot run (a model the CLI refuses) is refused when the Team is saved and again when it is used, before any worktree is made.
Why: the human wants to choose, per session, which model plans and which models work, and to keep several such setups: a lean one for speed or for a provider whose usage is low, and a thorough one for hard work, without editing Settings each time.
Rejected: one more global setting per knob, which cannot hold two setups at once; putting the model in each Profile, which ties the Worker roles to one provider; a Team per repo only, which makes the human copy it.

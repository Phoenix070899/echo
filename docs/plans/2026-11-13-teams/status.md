# Status: teams
Outcome: complete   Branch: chat-and-astryx   Base: 5a0875f
Review base: c4800718c3fd8060f1ffa05f1b57de2df477cc3b

| Task | State (pending/in_flight/done/blocked) | Fails | Commits | Verify | Notes |
|---|---|---|---|---|---|
| T01 | done | 0 | a8bf984 | pass (12 team tests; full crate 216+90 green) | deviations accepted: validate/save take fallback Cli; names may not start with `-`. P3: temp file name `.{name}.json.{pid}.part` shared by concurrent same-name saves in one process |
| T02 | done | 0 | a89636f | pass (224+94 green) | deviations accepted: no `echoctl agent open` exists, `--team` added to `echoctl ui orchestrator` (T08 must use it); chat reader/adoption use Team cli; renew_agent checks Team before ending session. P2 and P3s below |
| T03 | done | 0 | fe9addd | pass (227+99 green) | deviations accepted: method is `profiles.list` (not profile.list); chat_cli/recovery use Team choices; resume_worker calls pick_for in test daemons; fixed own deadlock in rows(). `cli::Choice::read` dead-code warning predates the plan. No findings |
| T04 | done | 0 | f15bec5 | pass (230+100 green; manual `echoctl team list/show` ok) | deviation accepted: `level` is user/repo plus a separate `repo` param (T06 must send {level:"repo", repo:<path>}). Methods: team.list {repo?}->{teams[]}; team.get {name,repo?}; team.save {name,team,level?,repo?}->{name,level,path,team}; team.delete {name,level(required),repo?} |
| T05 | done | 0 | e9d3e84 | pass (85 Swift tests; HubApp builds) | deviations accepted: form params tested via pure `openAgentParams` in HubCore; a Team with a problem is dimmed in the picker and its problem shown under the Name row. Not run visually (T08 f). New: HubCore/Teams.swift (Team, TeamChoice, openAgentParams), DaemonClient.teams(repo:), AppModel.loadTeams(repo:then:), Agent.team, ui-ux decision 0098. T06 needs team.save/delete/get client methods |
| T06 | done | 0 | 885add8 | pass (99 Swift tests; HubApp builds) | choices accepted: rules unset shows human's setting; Duplicate opens unsaved copy; "Keep in" picker only with a repo; page not run visually (T08 f). New: HubCore/TeamForm.swift, HubApp/TeamSettings.swift, DaemonClient.saveTeam/deleteTeam, ui-ux decisions 0099, 0100 |
| T07 | done | 0 | c480071 | pass (CONTEXT.md Team entry; 3 files, 25 insertions) | new decisions features/0082 (rotateAt as written, 0 = off) and 0083 (`echoctl ui orchestrator --team`, no `agent open`). P3: 0083 says "a phone" passes team; the shipped phone page does not (the API allows it) |
| T08 | done | 0 | no commit (HEAD c480071) | pass (230+100 cargo, 99 Swift, fmt clean, /tmp/hubk* gone, no hubk tmux, tree clean) | naruto's smoke (a)-(e) on real Kiro in a KIRO_HOME scratch dir: kiro-lean Orchestrator `--model claude-sonnet-5.5 --effort medium`; naruto Worker `claude-sonnet-5.5 high`; ino Worker `claude-haiku-5.5 low` (ended blocked: no Task, Profile behaviour); throwaway Team `kiro-smoke` showed `# Team instructions` after the rules and before the repo line; edited naruto model then `worker resume` ran `claude-haiku-5.5`; claude-lean row stored team with empty cli/model. (f) HubApp builds, 99 tests; screenshots in /tmp/echo-teams-smoke-shots/ (new-session-sheet.png, orchestrator-header-team-kiro-lean.png); Teams page NOT captured (needs focus/click). Sasuke reviewed by code and cleanup state, not by re-running Kiro |

## Unresolved review findings
- T01 P3: temp file name collision for concurrent same-name saves in one process (fails with an error, no corruption).
- T02 P2: the daemon's verifier gate in `start_worker` (daemon.rs ~L2067, `flag("verify") && Rules::from(settings).review`) ignores the Team's `review` rule, so a Team with `review:true` over a human `review:false` tells the Orchestrator to verify but the daemon never runs the verifier. Fix: resolve `review` via `Rules::with_team` with the Worker's agent Team. Not in any task's stated goal; kept out of scope per the plan.
- T02 P3: a broken Team makes `renew_if_due` retry `renew_agent` every `watch_agent` tick with a stderr line (session safe).
- T02 P3: `agent_stored_cli` re-reads and validates Team files on every chat read/adoption call.
- T05 P2: ContentView.swift `meta` (~L826-836): a stopped Orchestrator's panel header ("Stopped, a shell in <place>") returns before the Team text, so it does not name its Team (goal and decision 0098 say the header names it). Fix: add `agent.team` to the `!agent.live` branch.
- T05 P3: with no usable Team and an earlier Normal-mode model pick, `openAgentParams` still sends the hidden `form.model` for an Orchestrator.
- T05 P3: `TeamChoice.remember` runs before the open succeeds.
- T05 P3: `teamLine` lists every problem Team on every open; may crowd out the picked Team's summary.
- T06 P3: decision 0099 says Echo checks only that the Team has a name, but TeamForm.blocker also blocks a duplicate Profile row and a non-numeric "Renew at" (justified; a later decision can restate).
- T06 P3: `form != saved` includes `nextOverrideID`, so adding then removing an override leaves "Not saved yet" with Save enabled.
- T06 P3: picking another Team row discards unsaved edits without a prompt; the page opens on a blank New Team form and returns to it after a delete.

## Blocked: reason → what unblocks
## Suggested next steps
- Fix the T02 P2 (Team `review` rule vs the verifier gate) and the T05 P2 (stopped Orchestrator header) in a follow-up.
- Capture the Teams page in the app by hand (it was not screenshotted) and try the picker's disabled-item behaviour on macOS.
- A real `lee` Worker was not run; `ino` covered the Haiku check.

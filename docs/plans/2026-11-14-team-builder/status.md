# Status: team-builder
Outcome: complete   Branch: plan/team-builder   Base: 05c92fc35f332741bb0b2f55e1f5caec71b58506
Review base: 78887593d33d436d57391acfe8a1c639e455ec48

| Task | State (pending/in_flight/done/blocked) | Fails | Commits | Verify | Notes |
|---|---|---|---|---|---|
| T01 | done | 0 | 884523d | pass | P3 only: 0086 line 12 and 0087 line 6 hold several sentences per line; 0086 carries `Supersedes: features/0055` (accepted). |
| T02 | done | 0 | 5129c69 | pass (action:: 6; crate 236+100) | P3: dead-code warnings (action::list now called from launch.rs). |
| T03 | done | 0 | 643979d | pass (team:: 24; crate 247+100) | lessons/writes are Option<bool>, replaceRole bool; verify Member without parent refused. |
| T04 | done | 0 | 89b347d | pass (crate 250+101) | P3: `member` not in the `needs` JSON. |
| T05 | done | 0 | c184eae | pass (crate 253+105) | No findings. |
| T06 | done | 0 | 76d6af8 | pass (profile:: 24, cli:: 43; crate 260+105) | P3: no pick_for-level test for the Member-gone fallback. |
| T07 | done | 0 | 23215ce | pass (launch:: 6, settings:: 5; crate 264+105) | P3: hand-off footnote wording. |
| T08 | done | 0 | c081f47 | pass (crate 264+109) | P3: unrunnable verify Member fails verification start, no sasuke fallback (per goal). Bug file docs/bugs/0075. Internal start_worker params `member`, `bare` judged harmless. |
| T09 | done | 0 | ab0a33e | pass (crate 265+109) | Resolution equivalence confirmed. Two P2 (see findings). |
| T10 | done | 0 | 320f288 | pass (crate 265+114) | P2: temporary pane mapping until T13 (intended; resolved by T13). |
| T11 | done | 0 | 71cd491 | pass (app tests 121; HubApp builds) | P3: blocker does not check `worktree` (daemon does). |
| T12 | done | 0 | 7987f98 | pass (app tests 173; HubApp builds) | No findings. API: TeamTree, Action.shipped, TeamTemplate, ProviderPreset, TeamForm.starting. |
| T13 | done | 0 | bba694a | pass (app tests 179; HubApp builds) | Two P2 + P3s. New: TeamsSection.swift, HubCore SettingsNavigation.swift. `TeamSettingsModel` lives on AppModel (`teamSettings`). Not run in the app. |
| T14 | done | 1 | 12493d7 | pass (app tests 206; HubApp builds) | Attempt 1 built and tested but left the tree uncommitted ("My standing rules forbid running `git commit` in this workspace"); attempt 2 reviewed and committed it. Four P2. New: HubCore TeamMembers.swift, HubApp TeamInspector.swift. Old Profiles entry removed. |
| T15 | done | 0 | 014a39e | pass (app tests 246; HubApp builds) | P2: key auto-repeat. Three-column layout; HubCore TeamTreeEditing.swift, HubApp TeamTreeView.swift. Key handling and focus NOT run in the app. |
| T16 | done | 0 | afa9a90 | pass (app tests 290; HubApp builds) | P2: `.onDrag` + `.onDrop(of:delegate:)` instead of `.draggable`/`.dropDestination`; never run. Fallbacks cover all but chip-insert-between-rows. New: HubCore TeamTreeDrop.swift, HubApp TeamPalette.swift. REAL DRAGGING IS A CHECK FOR THE HUMAN. |
| T17 | done | 0 | a69fff8 | pass (app tests 304; HubApp builds) | Two P2. New: HubApp NewTeam.swift (FlatSegmented), HubCore NewTeamSheet.swift. Sheet not run in the app. |
| T18 | done | 0 | 51f6a71 | pass (crate 265+114; app tests 304; HubApp builds; grep for .agents empty) | P2: no docs/bugs file for the confirmed-but-unfixed T09 profiles.list finding (README needs a "Fixed in" line, so it waits for the fix). P3 doc wording. Dead code removed: AgentSettingsModel.repo, SettingsView.refreshAgents(), WorkerProfile.replaces/.origin. |
| T19 | done | 0 | 7888759 | pass (crate 265+115; report exists; porcelain clean) | (1) fake-agent end-to-end test `a_team_of_members_is_built_used_edited_and_resumed_end_to_end` passes (verifier `check`, Member and Profile starts, edit and resume, team show tree). (2) Real Kiro run done: Worker w1 gave no Final Report (idle_prompt blocker, spec did not name `echoctl done`), w2 returned one; rows show Member scan, Profile hinata, claude-haiku-5.5, kiro; "Your Workers" section and the `check` path not exercised by a real model. (3) Visual check NOT done: the only app copy predates the Teams section and a new one needs `make -C app app`; no screenshots, no app UI and no real dragging exercised. Cleanup done (daemon shut down, /tmp/hubk* removed, echo-*.md removed); Kiro added session/log folders and pruned three old log folders in ~/.kiro on its own. P3: report sentence about a real Orchestrator's longer Task text is unbacked. |

## Unresolved review findings
- T01 P3: features/0086 line 12 and features/0087 line 6 break "one sentence per line" (committed files, not edited).
- T04 P3: `member` absent from `needs` JSON; add only if a later milestone wants it.
- T06 P3: no pick_for-level test for the Member-gone fallback.
- T07 P3: launch.rs hand-off footnote ("A Worker you start new gets the report quoted in its spec file") should say the Orchestrator quotes it.
- T08 P3: an unrunnable verify Member fails verification start with no sasuke fallback.
- T09 P2: `daemon.rs` `profiles.list` (~:1601) and `main.rs` `profile list --team` (~:427) resolve each Profile with `member = None`; for kiro-lean they now show naruto and sasuke as haiku/low (before: sonnet/high, sonnet/medium). Real Workers started through `member_for` are right. Fix: resolve through `team.member_for(&p.name)` in both listings, then add `docs/bugs/0076-*.md` (with "Fixed in") in the same change. The plan (T05) said these keep per-Profile resolution, so this is a plan gap, not a worker error; not widened by Kakashi.
- T09 P2: bare-`sasuke` verifier (writer with no stored Member, e.g. a user Profile not in the Team) on kiro-lean runs haiku/low, where `workers.profiles.sasuke` used to give sonnet/medium. Accept as 0086 semantics (record as deviation) or keep a `workers.profiles.sasuke` entry in kiro-lean.
- T09 P3: no test pins bare-Profile or Profile-list resolution under kiro-lean.
- T11 P3: Swift blocker does not check Member `worktree`; the daemon refuses a bad value.
- T13 P2: `TeamsSection.swift` `TeamsList`: Delete and Duplicate stay enabled on the Defaults entry and act on the last picked Team that is not on screen. Fix: disable both when `teams.pane != .team`.
- T13 P2: `UnsavedTeamModal` Return clash: the form's Save (`TeamSave`, `.keyboardShortcut(.defaultAction)`) stays enabled under the card, so Return may hit it instead of the card's Save. Fix: `.disabled(teams.asking)` on the section's Form. Unconfirmed without running the app.
- T13 P3: empty tap on the pristine "not saved yet" row; `pane` on AppModel reopens the last pane not the first Team; Defaults Model field text lost without Return when leaving (pre-existing); a failed re-read after a successful Save skips the follow-up step.
- T14 P2: Reset and Delete of a user's Profile copy are gone from the UI (only `echoctl profile reset`/file delete remain); "Edit shared role..." copies Echo's Profile into `~/.echo/profiles` and the UI cannot undo it. Fix: Reset/Delete button for a `yours`/`repo` Profile in `MemberSharedRole` (TeamInspector.swift).
- T14 P2: unchecking the last tool is silently ignored (no caption saying an empty list means the Profile's list applies; use Reset), and a toggle also copies the inherited list into the Member (marks the form changed with no real change). Fix: caption, and skip the write when the toggle result equals the current value (`MemberTools.toggled`, `MemberToolList`).
- T14 P2: `TeamForm.resolve` models `forceCli` as `defaults.forceCli && setting != .effort`; the daemon (`cli.rs:723` `overrides_profile`) applies it only when a settings file also names a `cli`. With forceCli on and no CLI set, the inspector shows "claude, your defaults" where the daemon uses the Profile's own CLI/model. Repo `.echo/settings.json` is not read.
- T14 P2 (fixed in T15 by `.id(member.id)`, runtime unconfirmed): CommitField draft carry-over between Members.
- T14 P3: orphan Profile file after discarding a New custom Worker; blank-instruction "Replace the role" note is wrong; `memberNotice` shows twice.
- T15 P2: `TeamTreeColumn.handle` uses `.onKeyPress(phases: [.down, .repeat])` (TeamTreeView.swift ~:90), so every command auto-repeats: holding Delete removes leaf Members without a prompt, holding `a` or `d` fills the Team to 24. Fix: let only `.select` through on `.repeat`.
- T15 P3: Caps Lock makes `a` and `d` do nothing (compare lowercased characters); misleading caption when a custom Worker's parent vanishes mid-create; Return on a shipped read-only Team shows the read-only caption.
- T16 P2: `.onDrag` + `.onDrop(of:delegate:)` on a Button row never run; `.onDrop(delegate:)` has no other use in the repo. Check by hand: drag starts from a row, line/fill placement, zones, forbidden cursor, caption, chip drop between rows, palette wrap at 330 pt.
- T16 P3: `TreeDragState.dragging` is cleared only on performDrop/end (stale payload after a cancelled drag; the drop itself stays safe); `TeamTreeView.swift` is 624 lines (move TreeDragState, TreeDropDelegate, MoveToMenu out); `parse` accepts any valid-ID profile in a chip payload (the daemon refuses an unknown Profile on save).
- T17 P2: `NewTeamSheet.nameProblem` (HubCore/NewTeamSheet.swift ~:70-77) checks only the winning entry per name: a hidden same-name user Team can be silently overwritten on Save (team::save has no exists check), or a new "Yours" Team can be shadowed by a repo Team of the same name. Fix: also refuse when `team.replaces.contains(kept)` and when the winner outranks `kept`.
- T17 P2: the sheet's Cancel (NewTeam.swift ~:53, `.keyboardShortcut(.cancelAction)`) and `UnsavedTeamModal`'s Cancel share Esc while the ask is up; Esc may close the sheet instead of the ask. Fix: `.disabled(teams.asking)` on the sheet's Cancel.
- T17 P3: global menu shortcuts (Command+N, Command+K, Fan Out) stay live while the sheet is up (same as the existing modals).
- T18 P2: no docs/bugs file for the unfixed T09 `profiles.list` finding (see T09; the bugs README needs a "Fixed in" line).
- T18 P3: README:151 says effort also comes from the pick and the settings files (only CLI and model do; effort: Member, Team `workers.profiles`, Team `workers`, Profile); SKILL.md says `team show` prints "what it runs on" but it prints only the Member's own cli/model/effort; `orchestrator.md:21` still says `worker start <profile>` (works as the fallback).
- T19 P3: the smoke report sentence "A real Orchestrator's Task text is longer than the one used here" is unbacked; soften or drop. The real run covered only the `scan` Member started from the CLI.

## Blocked: reason → what unblocks
(none; all 19 tasks done)
## Suggested next steps
- Human checks in the real app (never run): Teams section layout, tree keys and focus (Up/Down not switching sections), drag and drop (T16 used `.onDrag`/`.onDrop(delegate:)`), the New Team sheet, the unsaved-changes card, and the Member inspector; take the two `docs/screenshots/teams-*.png` then (T19 skipped them).
- Fix the P2 findings listed above in one follow-up (T09 `profiles.list`/`profile list --team` with `team.member_for` plus `docs/bugs/0076`; T13 Delete/Duplicate on Defaults and the Return clash; T14 Reset/Delete of a Profile copy, last-tool caption, forceCli model, CommitField; T15 key auto-repeat; T17 same-name check and Esc clash).
- Decide the bare-`sasuke` verifier model on kiro-lean (T09 P2).
- Decide the two T09 P2 findings and fix the T13 to T18 P2 findings after the run; none blocks later tasks. Real keyboard, focus, drag, sheet and layout behaviour of the Teams section (T13 to T17) has never been seen in the running app.

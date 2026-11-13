# Status: kiro-parity
Outcome: complete   Branch: chat-and-astryx   Base: ea02459
Review base: fda1f928fe6f682328777142954a2de155140e27 (latest sasuke reviewed_head; run started from 1f1b16f, later than base_commit ea02459). HEAD at finish: fda1f92.

| Task | State (pending/in_flight/done/blocked) | Fails | Commits | Verify | Notes |
|---|---|---|---|---|---|
| T01 | done | 0 | 9b3ab87 | pass (cargo fmt clean; 169 + 84 tests ok) | Root cause: kiro resume with an unrecorded id opened a plain default-agent session; fixed in cli.rs (no --resume-id without history) and profile.rs (Kiro resume message carries the Task). Bug 0070, decision 0076. Naruto left small Kiro session folders for the throwaway repo under ~/.kiro/sessions/3d6ce2593f31a07f/ (not deleted per rule). |
| T02 | done | 0 | 05fde3f | pass (cargo fmt clean; 183 + 86 tests ok) | kiro_chat.rs, decision 0077, fixtures, 2 daemon tests. |
| T03 | done | 0 | fe1bf44 | pass (file present, `Verdict: ACP`, no acp/kirousage processes) | ACP works: `_kiro/account/getUsage` after `initialize`; ~1.7 s. Signed-in check: `kiro-cli whoami` exit 0. Scratch KIRO_HOME avoids log-folder churn. |
| T04 | done | 0 | 705b31b | pass (cargo fmt clean; 195 + 89 tests ok) | kiro_usage.rs, fake-kiro-cli.sh, decision 0078, README. |
| T05 | done | 0 | fda1f92 | pass (`make -C app test`: 75 tests passed; `swift build --product HubApp` complete; cargo fmt clean) | Usage bar appends Kiro's entry last; ChatItem decodes `level`/`denied`; ui-ux decision 0097. `make -C app app` deliberately NOT run (it would replace the human's running Echo, pid 77779). |
| T06 | done | 0 | none (no fixes needed) | pass (plan verify with the untracked plan folder excluded from the cleanliness test: no /tmp/hubk*, no hubk tmux, no kiro-cli acp, fmt clean, 195 + 89 tests, 75 Swift tests, git clean) | Evidence below (as reported by naruto; sasuke could not re-run real Kiro). |

## T06 smoke evidence (naruto's report, real Kiro on claude-haiku-5.5, HUB_STATE=/tmp/hubk)
- (a) `chat.read` on Worker w1: `supported:true`, `start:0`, `end:20652`; items user (from orchestrator, the spec), tool Bash `echo hi > hello.txt` + result "Exit Code: 0", reply "I created hello.txt ...", plus `echoctl done` tool/result pairs. After a second message (two turns, `end:24681`): `limit:4` page gave `start:20652, more:true` (turn two: user, Bash `cat hello.txt`, result, reply); `before:20652` page gave `start:6461, more:true` with the end of turn one.
- (b) w2 (`echo a > a.txt`, `sleep 60`, `echo b > b.txt`, `echoctl done`): `worker close` then `worker resume w2` -> "Resumed w2"; same session `sess_7003a351...`; chat shows the interrupted `sleep 60`, an interrupt event, the resume text with "Your Task:" and the whole Task, the model re-checking a.txt, then finishing; w2 ended `done` about 75 s later, b.txt exists.
- (c) `usage` after `usage.refresh` with the real login: `{"limits":[{"name":"Session","percent":0,"resets":null},{"name":"Week","percent":100,"resets":"Nov 13 at 11pm"},{"name":"Week (Fable)","percent":2,"resets":"Nov 13 at 11pm"},{"detail":"650.15 of 2000","name":"Kiro credits","percent":32,"resets":"Dec 1"}],"error":null,...}`. The scratch home `/tmp/hubk/kiro-home` works for this sign-in (`whoami` exit 0, IamIdentityCenter). The first `usage` call right after start returned empty limits until the refresh.
- (d) Swift decode check of the saved real `chat.read` and `usage` JSON via a temporary test (deleted, not committed): chat pages and older-page merge decode, `interrupt` event and `from:"orchestrator"` read, usage decodes with tooltip "Kiro credits: 650.15 of 2000 credits, resets Dec 1". A separate test copy `dev.agenthub.Echo.test` (in /tmp, removed) ran against the daemon; `screencapture -l 3609` showed top bar "1 Worker running · Session 0% · Week 100% 2h 35m · Kiro credits 32% 17d 3h" and the Kiro Worker's chat tab with the From Orchestrator bubble, a Bash tool card and the Working row. The screenshot was not saved into the repo.
- Cleanup confirmed by naruto and sasuke: daemon shut down, test app stopped, /tmp/hubk* gone, echo-*.md files removed from ~/.kiro/agents (only the human's seven agents and agent_config.json.example remain), human's pid 65379, Echo pid 77779 and kiro-cli TUI untouched.

## Process notes
- For T02, T04 and T05 I mistakenly dispatched sasuke in the same call as naruto, and for T02 and T04 rewrote status.md while a naruto was running. In all three cases a second sasuke was run strictly after naruto finished, with the same pass results; those second verdicts are the ones recorded. The T03 review (docs-only verify) was also dispatched next to T04's naruto. In some of those dispatch prompts I named commit SHAs before naruto had reported them; the sequential reviews confirmed the SHAs.
- This status.md is untracked and was never committed (workers must not touch the plan folder), so a literal `[ -z "$(git status --short)" ]` fails by this one file; with the plan folder excluded the tree is clean.

## Unresolved review findings
- T01 P2 (daemon.rs `resume_worker` ~L1961-1969 + profile.rs `resumed`): a resumed Kiro Worker is re-sent its original Task even after `worker next` or verify feedback gave it a later one (`next_task` never updates `workers.spec`). Fix idea: use the latest task input, or update `spec` in `next_task`.
- T01 P3: an empty spec yields "Your Task:\n\n" with nothing after.
- T02 P2 (kiro_chat.rs `Lines::items` ~L66-83): a duplicate generic "Error: the turn failed." event can show when the `displayError` line and `turn_end` land in different polls/pages (`error_shown` resets per read). Cosmetic. Fix idea: drop the generic note when a `displayError` precedes in the same turn, or give it a stable id; add a split-range test.
- T02 P3: an agent with no stored CLI in a Codex-configured repo now reads `supported:false` (follows from `cli::recovered`, accepted in 0077).
- T03 P3: cold-cache SUM timing and the not-signed-in ACP reply were not measured (doc says so).
- T04 P3: `kiro_usage.rs credits()` floors `used / cap * 100.0`, so exact values like 580 of 2000 show 28 instead of 29 (fix: floor `used * 100.0 / cap`).
- T04 P3: `end()` does not `killpg` when the child exits on its own (grandchild could linger; none seen).
- T04 P3: decision 0078 says no fallback to the default home, but `scratch_home()` returns None when the dir cannot be created and the child then uses the default home. Fix code to fail the read, or add a superseding decision.
- T04 P3: a non-zero `whoami` clears the last good entry (deliberate per 0078).
- T05 P3 (first, overlapping review only; the sequential review did not repeat it): `UsageInline.helpText` now lists `usage.shown`, so a third Claude limit (e.g. "Week (Opus)") is no longer in the tooltip.
- T06 (smoke, pre-existing, not from this plan; confirmed by sasuke via blame to ad3df82a): a forced-Kiro Worker's header shows the Profile's model/effort ("claude-sonnet-5-5, high effort", chip "Sonnet") instead of the model it actually ran (haiku-5.5), because the snapshot `model` falls back to the Profile (daemon.rs ~L2666-2667) and `effort` always comes from the Profile; neither follows forceCli (decision 0075). No docs/bugs file was written for it.
- T06 observations: the resume message (whole Task) shows as one long `event` in the chat; a Kiro Orchestrator's chat said "Nothing said yet" during about a minute of watching.
- Stray state: Kiro's own session folders from the smoke runs and a few log folders remain under ~/.kiro (sessions/3d6ce2593f31a07f/ and others, logs); not deleted because only echo-*.md may be removed. Safe to delete by the human.

## Blocked: reason → what unblocks
none

## Suggested next steps
- Write a docs/bugs file for the model/effort header defect and fix it with a `cli` field in the snapshot.
- Fix the T01 P2 (resume repeats the original Task) and T02 P2 (duplicate error note); both are small.
- Fix the T04 percent flooring and align decision 0078 with `scratch_home()`.
- Decide whether to commit this status.md or leave it out of the tree.

# Status: kiro-fixes
Outcome: complete   Branch: chat-and-astryx   Base: 7882ad7
Review base: 92a2f1879c53d91264b45de0b5c01b88a4778c3f

| Task | State (pending/in_flight/done/blocked) | Fails | Commits | Verify | Notes |
|---|---|---|---|---|---|
| T01 | done | 0 | 0f8c2c6 | pass (fmt clean; 198 + 89 tests ok) | Decision 0079, bug 0071. P3: next_task stores the Task before hand_over, so a failed hand_over leaves a Task the Worker never got as "current". P3: Workers stored before the `task` column resume on workers.spec (stated in 0079). Process note: first sasuke call was sent in parallel with the naruto by mistake and discarded; the verdict is from the re-run after the naruto finished. |
| T02 | done | 0 | ad276bb | pass (fmt clean; 202 + 89 tests ok) | Bug 0072. Fix is daemon-side (kiro_chat.rs `has_message`, 64 KiB look-behind; chat.rs parser closure gets the byte offset); Swift untouched, judged correct by sasuke. Same process note: first sasuke call was sent too early and discarded; verdict is from the re-run. |
| T03 | done | 0 | 288e340 | pass (fmt clean; 204 + 89 tests ok) | Bug 0073. Rounding in kiro_usage::credits; scratch home failure gives Outcome::Skipped (no child, one stderr line, last value kept). P2: decision 0078 still says "floored"; no superseding decision. Naruto ran a stray `git stash` + `pop`; sasuke confirmed stash list empty and nothing lost. |
| T04 | done | 0 | 92a2f18 | pass (fmt clean; 204 + 90 Rust tests ok; Swift 76 tests ok) | Bug 0074. `rows` calls cli::pick per Worker with pick_for's inputs; optional `cli` on the row only when not claude; Swift `modelLine` reads "kiro: <model>, <effort> effort". Same process note: first sasuke call was sent too early and discarded; verdict is from the re-run. |
| T05 | done | 0 | none (no fixes needed) | pass (verify command exactly as in the plan: no /tmp/hubk*, fmt clean, 204 + 90 tests ok, Swift 76 tests ok, tree clean; `swift build --product HubApp` complete) | Real-Kiro check of T01 passed: after `worker task` gave a second Task (TASK-BRAVO-TWO), interrupt and `worker resume`, messages.jsonl line 29 of the Kiro session carries only BRAVO-TWO (line 2 ALPHA, line 20 BRAVO). The plan said `worker next`; the CLI command is `worker task`. Constraint deviations: see below. |

## Unresolved review findings
- T01 P3: `next_task` (crates/hub/src/daemon.rs ~2061) stores the Task with `insert_task` before `hand_over`/`launch`; if `hand_over` fails, a later Kiro resume would repeat a Task the Worker never received.
- T01 P3: Workers from before the `task` column resume on `workers.spec` (documented in decision 0079).
- T01: no test proves `next_task` calls `insert_task` (HUB_TEST_AGENT forces Claude). Real Kiro: only the resume path was checked (T05), not `worker next` from the Orchestrator's side nor verifier feedback.
- T02 P3: crates/hub/src/kiro_chat.rs `has_message`/`LOOKBACK`: if more than 64 KiB lies between the `displayError` and its `turn_end` and neither is in the polled range, a mid-turn poll shows the generic line while a whole read shows the message. Not reachable with real Kiro output. A comment on `LOOKBACK` stating the limit was suggested.
- T02 P3: in-range `error_shown` flag ignores `executionId` while the look-behind checks it; theoretical only.
- T03 P2: `docs/decisions/features/0078` line 7 says the percent is "floored as Kiro's own figure is"; the code now rounds. Decisions are never edited, so a new `features/00NN` decision superseding only that clause is needed (`round(used * 100 / cap)`; 580 of 2000 reads 29; 1990 to 1999 of 2000 now read 100, which the Swift side shows red from 90 so no UI change). Not in any task's scope; left for the human or a follow-up.
- T03 P3: `docs/research/kiro-cli-usage-spike.md` lines 67, 75, 125 still describe a floored percent (a dated research record).
- T04 P3: an unforced Worker whose Profile names no model but whose settings.json does now shows the settings model (previously null); more accurate, not covered by the unchanged-row test.
- T04 P3: the row is computed from the current settings at snapshot time, so flipping `forceCli` while a Worker runs changes its header but not what it runs on (recorded in bug 0074 "Limit").
- T04 P3: `rows` calls `cli::pick` even when `profile::load` fails, where `pick_for` errors; affects only the header of a Worker that cannot spawn.
- Not checked on a real Kiro: T02 (a failed turn), T03 (credits and scratch home), T04 (header with forceCli). They have unit/integration tests only.

## Standing-constraint deviations by workers (for the human)
- T05 naruto found an idle `echoctl daemon` (pid 19412) already running with `HUB_STATE=/tmp/hubk` that it had not started, judged it a leftover, and stopped it with `echoctl shutdown --force` so `/tmp/hubk` could be removed. This breaks "leave a daemon not started by you alone". It was not the human's daemon (pid 55845 still runs, as do the Echo app pid 77779 and the 10 `echo-*` tmux sessions), but whose it was is unconfirmed.
- T05 naruto ran real Kiro without KIRO_HOME, so it created session files in the human's `~/.kiro`: `sessions/6c28c34469dcf1ee/`, `sessions/cli/sess_3c3dca97-….history`, `session-index/6c28c34469dcf1ee.jsonl`, new `logs/` entries, `enterprise-management/`. The constraint allowed only `echo-*.md` agent files there. Its agent file `echo-4b93ca71f43bbc35.md` was removed. It read only that one session's messages.jsonl, read-only.
- T03 naruto ran a stray `git stash` and `git stash pop`; nothing lost (stash list empty).
- Kakashi (me) sent three sasuke reviews (T01, T02, T04) in the same step as the naruto, with a sha I did not have yet; all three were discarded and re-run after the naruto finished, so the verdicts used are the sequential ones.

## Blocked: reason → what unblocks
None.

## Suggested next steps
- Add the decision superseding 0078's "floored" clause (T03 P2).
- Decide whether to delete the leftover Kiro session/log files from T05 in `~/.kiro`.
- Confirm the stopped `/tmp/hubk` daemon (pid 19412) was not something you needed.
- Leftover pre-existing test daemon pid 65379 (`target/debug/echoctl daemon`, from 6:24PM, socket gone) and `/tmp/hubt-*` dirs from earlier runs, not from this plan.

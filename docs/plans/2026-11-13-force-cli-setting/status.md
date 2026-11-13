# Status: force-cli-setting
Outcome: complete   Branch: chat-and-astryx   Base: 81fff6b
Review base: ea02459 (latest sasuke reviewed_head)

| Task | State (pending/in_flight/done/blocked) | Fails | Commits | Verify | Notes |
|---|---|---|---|---|---|
| T01 | done | 0 | 9ece39b | sasuke pass: fmt clean, 165 + 84 passed | Naruto also changed cli::recovered to follow forceCli (beyond brief); sasuke judged it correct and in scope. P3 findings below |
| T02 | done | 0 | ea02459 | sasuke pass: 70 Swift tests passed, Echo.app built | No ui-ux decision record written. Caveat: with no cli saved the picker shows claude but stores nothing, so the switch forces nothing (per 0075) |
| T03 | done | 0 | none (no fixes needed) | sasuke pass: no hubk leftovers, fmt clean, 165 + 84 and 70 tests passed, tree clean except this file | Smoke evidence (naruto's report): forceCli+kiro/claude-haiku-5.5, `worker start naruto` without --cli ran `kiro-cli chat --agent echo-... --model claude-haiku-5.5`, ended done, hi.txt = hi, commit 47da236 in the throwaway repo; forceCli false made `profile list` show naruto on claude. Plan's `--spec`/`--profile` flags do not exist; the real form is `--spec-file <file> naruto`. echoctl has no settings command, so settings.set went over the daemon socket. Workers have no tmux pane without an attached Echo window; the kiro-cli process under the holder was the evidence |

## Unresolved review findings
- T01 P3: `recovered` (daemon.rs ~L1020-1040) follows current settings, not the launch-time ones; flipping forceCli while a forced Worker runs and then restarting the daemon adopts it with the wrong cli. Same limit as resume today; no fix asked.
- T01 P3: a Profile's `effort` and `tools` still apply to a forced agent; intended (decision covers cli and model only).

## Blocked: reason → what unblocks
None.

## Suggested next steps
- Commit this status.md (it is untracked) if the plan folder is meant to be tracked.
- A stray daemon (HUB_STATE=/tmp/hubt-60304-kirosid, pid 65379, fake agent) from another test run was left running; it is not from this plan.
- Consider an `echoctl` settings command so forceCli can be set without the raw socket.
- Mark the draft PR ready only after self-review and `/review` per the stated workflow.

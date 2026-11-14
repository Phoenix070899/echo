# Team builder smoke runs

Date: 2026-11-14. Branch `plan/team-builder`, task T19 of `docs/plans/2026-11-14-team-builder/`.
Decisions exercised: features/0084 (Members), 0085 (a Member's choices come first), 0086 (a verify Member replaces sasuke), 0087 (Actions).

| Run | Result |
|---|---|
| 1. End-to-end test with the fake agent | Done, passes |
| 2. Real run on Kiro | Done; first Worker gave no Final Report, second did (finding 1) |
| 3. Visual check of the Teams section | Not done: the only test copy available predates the Teams section |

The app UI was not exercised at all, and no real mouse drag happened. Runs 1 and 2 drive the daemon through `echoctl` and the socket only.

## 1. Integration test

`a_team_of_members_is_built_used_edited_and_resumed_end_to_end` in `crates/hub/tests/daemon.rs`, with `HUB_TEST_AGENT=tests/fake-agent.sh` and `HUB_STATE=/tmp/hubt-<pid>-smoke-team`.

What it does, in order:

1. Saves the Team `smoke` over the socket (`team.save`, level `user`) with the Members `scan` (hinata), `build` (naruto) > `check` (sasuke, model `claude-haiku-5-5`), and `run` (lee).
2. `echoctl team show smoke` prints `scan`, `build`, `run` at one indent and `check` on the line after `build`, one level deeper.
3. Opens an Orchestrator on `smoke` and starts `build --verify` with the spec `next FAILME`. The Orchestrator hears `Verified by w3 (check): pass.`, never "sasuke". w2 and w3 are the `check` Member's Workers (row `member` = `check`, `profile` = `sasuke`, `model` = `claude-haiku-5-5`).
4. Starts `scan` (a Member id) and `lee` (a Profile name; the first Member using it is `run`). w4 shows `scan`/`hinata`/`claude-haiku-5-5`; w5 shows `run`/`lee`.
5. Edits the Team over the socket: `scan`'s model becomes `claude-sonnet-5-5` and `run` is removed. `team show` no longer lists `run`.
6. `echoctl worker resume w4` and `w5` both print `Resumed ...`. w4's row now shows `claude-sonnet-5-5`. w5 keeps `member` = `run` and `profile` = `lee` and takes lee's own model (features/0084's fallback), with no error.

```
$ ~/.cargo/bin/cargo test -p echoctl --test daemon a_team_of_members_is_built
test a_team_of_members_is_built_used_edited_and_resumed_end_to_end ... ok
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 114 filtered out; finished in 7.73s
```

The full `cargo test -p echoctl` result is in the task's verify run.

## 2. Real run on Kiro

Setup: `kiro-cli 3.3.0`, signed in (`kiro-cli whoami`: IAM Identity Center). Before starting, `pgrep` and `tmux ls` (read-only) showed the human's own daemon (`HUB_STATE=/Users/dung.nguyen/.echo`), its Claude Orchestrator and `echo-*` tmux sessions; nothing of that was touched. Everything below ran under `HUB_STATE=/tmp/hubk`, in the throwaway repo `/tmp/hubk-work/zzsmoke` (one commit, README of two lines), with the debug `echoctl` of this branch. `KIRO_HOME` was not set (`~/.kiro`).

Team, saved over the socket (`team.save`, level `user`):

```
$ echoctl team show smoke
smoke
orchestrator.cli: kiro
orchestrator.model: claude-sonnet-5.5
workers.cli: kiro
workers.model: claude-haiku-5.5
workers.effort: low
members:
  scan  scan  hinata  claude-haiku-5.5
  build  execute  naruto  claude-haiku-5.5
    check  verify  sasuke  claude-haiku-5.5
```

Orchestrator opened with `agent.open` (`kind: orchestrator`, `team: smoke`) and a Worker started under it with `HUB_AGENT=1`:

```
$ HUB_AGENT=1 echoctl worker start scan --spec "In one sentence: what is the answer constant named in README.md? Reply with a Final Report." --title "smoke question"
Started w1 (scan from hinata: smoke question) in /private/tmp/hubk-work/zzsmoke
```

The processes Echo started (`ps`, trimmed):

```
kiro-cli chat --v3 --agent echo-a0d393904e3bbb9a --model claude-sonnet-5.5 --effort high --trust-workspace      (Orchestrator)
kiro-cli chat --v3 --agent echo-45eca66523528d22 --model claude-haiku-5.5 --effort low --trust-workspace <spec>  (w1, w2)
```

Attempt 1 (w1). The Worker read the README and answered on screen ("The answer constant named in README.md is 42"), then stopped at its input box. No `echoctl done` was run, so the Orchestrator got a blocker, not a Final Report:

```
#1 blocker from w1 (scan (hinata): smoke question)
Blocked: idle_prompt
Its turn ended with no Final Report.
```

Attempt 2 (w2), same Member, with a spec that tells the Worker to run `echoctl done`:

```
$ HUB_AGENT=1 echoctl worker start scan --spec "Read README.md and say in one sentence what the answer constant is. When done, run echoctl done --state done with State, Changed, Verified lines as your contract says." --title "smoke question 2"
Started w2 (scan from hinata: smoke question 2) in /private/tmp/hubk-work/zzsmoke
$ echoctl status --json     (fields trimmed)
w2  member=scan  profile=hinata  model=claude-haiku-5.5  cli=kiro  state=done
    finalReport="State: done\nChanged: none\nVerified: read README.md, which states 'The answer constant is 42.'"
$ HUB_AGENT=1 echoctl worker list
w1    scan (hinata) running  108s quiet  in place  smoke question  [blocked: idle_prompt]
w2    scan (hinata) done     38s quiet  in place  smoke question 2
```

Passed: both rows show Member `scan`, Profile `hinata`, model `claude-haiku-5.5`, CLI `kiro`, and the Orchestrator ran on `claude-sonnet-5.5`; a Final Report arrived for w2. The Orchestrator itself was not asked to do anything; the Workers were started from the CLI, so the generated "Your Workers" prompt section was not read by a real model in this run. The `check` verify path was covered by the fake agent in run 1, not on Kiro.

Used twice, as the task allows. No retry beyond that.

Cleanup, in CLAUDE.md's order: no tmux session of mine existed (the daemon holds the agents itself); `echoctl shutdown --force` with `HUB_STATE=/tmp/hubk` stopped the daemon and its three Kiro processes; then `/tmp/hubk` and `/tmp/hubk-work` were removed, and so were the two `echo-*.md` agent files the run created under `~/.kiro/agents` (none of `echo-*` existed before). Kiro itself wrote to `~/.kiro` while it ran (a `sessions/f846b287644c0286` folder, a `session-index/f846b287644c0286.jsonl`, three new `logs/` folders, and it pruned three old ones). Those are Kiro's own files and were left alone.

## 3. Visual check

Not done. The only test copy available is `app/build/Echo.app`, built 14 Nov 07:38, and it has no Teams section: the Swift commits for it (`bba694a` to `a69fff8`) are all later, and `strings` on its binary finds none of the Members or `team.actions` code. A current copy needs `make -C app app`, which this task forbids. CLAUDE.md names no other way to build a test copy. So `docs/screenshots/teams-tree.png` and `teams-inspector.png` do not exist, and nothing was opened, captured or typed into on the human's Mac. To do it later: build the app, then follow `app/scripts/measure-switch.sh` for the test bundle id, `open -g`, `screencapture -l` and `echoctl ui settings teams`.

## Findings

1. A Kiro Haiku Worker can end its turn with the answer on screen and no `echoctl done` (w1). The Worker Contract in its agent file says "Nothing you print in your terminal reaches the Orchestrator: your Task is finished only when you have run `echoctl done`", yet a Task whose spec said "Reply with a Final Report" was read as "answer in the terminal". The daemon handled it as designed (an `idle_prompt` blocker whose text says the turn ended with no Final Report), and the spec that named `echoctl done` worked. This is model behaviour on a terse spec, not a Member bug; no change was made. A real Orchestrator's Task text is longer than the one used here.
2. No defect was found in Members, the Member lookup, the Team's model order, the verify Member or the resume fallback in these runs.

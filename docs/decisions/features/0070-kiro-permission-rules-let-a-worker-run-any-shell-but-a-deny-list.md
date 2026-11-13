# Kiro permission rules: a Worker runs any shell but a deny list, an Orchestrator only its echoctl commands

Decided: 2026-11-13
Status: accepted

A Kiro Worker reads anywhere, writes only in its checkout and the hub and memory folders, and runs any shell command except `KIRO_DENIED_COMMANDS` (`rm -rf *`, `rm -fr *`, `git reset --hard*`, `sudo *`, and `curl` or `wget` piped into `sh` or `bash`), the same commands `settings/worker.json` asks about for Claude.
A shell rule matches the command text and never a folder, so the deny list is the Worker's guard; `fs_read` on `**` stops the second prompt a shell command raises for its folder.
The deny list is blocked without a prompt, so no answer can unblock it; a Worker that needs one finishes with `echoctl done --state blocked` and the command in its report.
A Kiro Orchestrator runs without a prompt only `echoctl wait`, `worker`, `reply`, `brief`, `inbox`, `status`, `sessions`, `profile` and `ui`, under the same deny list. Every other shell command asks and shows in Needs you.
Those commands are named one by one, never `echoctl *`: the spike did not show whether a glob also matches a chained command.
A Normal session gets rules only for the folders Echo gave it.
Why: a Worker works unwatched and would stall on every command, and an Orchestrator calls `echoctl` every few minutes and would hold up its Workers' messages if each call asked.
Rejected: `echoctl *` for an Orchestrator.

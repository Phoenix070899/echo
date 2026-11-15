# Echo keeps its own login for Claude and Codex, and agents fall back to yours

Decided: 2026-11-15
Status: accepted

Settings > Providers, right after Teams, lists Claude, Codex and Kiro with who their agents run as: Echo's own login, yours, or none.
Sign In runs the CLI's own sign-in (`claude auth login`, `codex login`) in a terminal under its row, on Echo's config folder `accounts/<cli>` in the daemon's state; Echo stores no secret itself.
Echo's folder links to everything in your own config folder but the login (`.credentials.json`, `auth.json`), so settings, instructions, skills, plugins, transcripts and Codex sessions are the same; Claude's `.claude.json` starts as a copy of yours without its account.
Claude Code keeps Echo's login in its own keychain item (`Claude Code-credentials-<hash of the folder>`), so signing Echo in or out never touches yours.
While Echo's login is signed in, every agent and Worker starts with `CLAUDE_CONFIG_DIR` or `CODEX_HOME` on Echo's folder, and `claude -p /usage` for the title bar runs on it too; a plain terminal keeps yours.
With no Echo login, agents run on yours, as before; running agents keep the account they started with, and Sign Out (asked first) sends new agents back to yours.
The daemon reads each login when it starts, when Settings asks, and when a sign-in ends; `echoctl providers` prints the same.
Kiro keeps one login for the whole Mac whatever `KIRO_HOME` or `KIRO_DATA_DIR` say, so Echo only shows it and never signs it in or out.
Why: the human wants agents to run on an account picked for Echo, apart from the one in their own terminal.
Rejected: Echo doing each provider's OAuth itself and holding the tokens; separate transcripts for Echo's login, which would also split Claude Code's per-project memory and the chat views that read them; moving Kiro's login by giving it another HOME, which takes every other dotfile with it.

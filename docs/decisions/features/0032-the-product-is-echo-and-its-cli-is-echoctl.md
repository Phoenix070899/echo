# The product is Echo, its CLI is echoctl, and its state lives in ~/.echo

Decided: 2026-10-27
Status: accepted

The name Agent Hub is gone: the product, the GitHub repo (`Phoenix070899/echo`), and the docs say Echo.
The CLI is `echoctl`, not `hub` and not `echo`: `echo` is a shell builtin, so a binary of that name never runs.
The state folder is `~/.echo`; `HUB_STATE` still overrides it.
State from before the rename moves from `~/.agent-hub` the first time no daemon holds its `hubd.lock`, and `~/.agent-hub` stays as a link to it, because Worker worktrees and the paths in `hub.db` name the old folder.
`ECHO_REPO` replaces `AGENT_HUB` as the override for where the repo is.
The domain words Hub Daemon and Hub Session, `HUB_STATE`, `hub.db`, `hubd.sock`, the `crates/hub` folder, and the bundle id `dev.agenthub.Echo` keep their names: changing them buys nothing and would reset the human's saved settings.
Why: the human wanted one name for everything.

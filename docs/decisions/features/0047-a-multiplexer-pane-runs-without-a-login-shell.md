# A multiplexer pane runs its line with the daemon's environment, not through a login shell

Decided: 2026-11-02
Status: accepted

Supersedes: features/0018's "replaces itself with a login shell running it", because that shell took about 200 ms on every first visit to an agent.
`echoctl mux` asks the running daemon for `shell.env` and runs the multiplexer line with `/bin/sh -c`, with that environment over the pane's own.
`shell.env` is the daemon's environment, which is the human's since the daemon starts from a login shell (bugs/0036), less agent markers, `TERM`, `COLORTERM`, `TERMINFO`, and the `TERM_PROGRAM` and `TERM_SESSION_ID` of the terminal that started the daemon (bugs/0027).
With no daemon to ask, or one too old to answer, it runs the line through a login shell as before; it never starts a daemon itself, which would get Echo's bare environment.
Why: the multiplexer needs the human's PATH and locale, and the daemon already has them, so reading them again on each pane only cost time.

# A terminal holder owns every terminal, so agents outlive the Hub Daemon

Decided: 2026-10-31
Status: accepted

Supersedes: adr/0004's clause that a daemon crash loses live Workers, which then resume with `claude --resume`, because restarting the daemon (an update, a crash) killed every agent mid-turn.
`echoctl holder`, started by the daemon in its own session, owns every agent's, Worker's, and shell's PTY: it spawns, drains, resizes, and kills them, and keeps the last MiB of each one's output; it parses nothing and holds no policy.
The daemon talks to it over `holder.sock`, one connection per terminal, keyed `w12`, `a3`, `s3`: one JSON request line, then length-prefixed frames (holder.rs).
A starting daemon adopts every terminal the holder kept, rebuilds its screen from that tail, and resizes it one row smaller and back so a full-screen program redraws; only a live Worker whose terminal is gone is marked lost.
`echoctl shutdown` stops only the daemon; `--force` also kills every terminal and the holder.
The holder exits after 30 s with no terminals; one of another protocol version (`holder::VERSION`) is not replaced while it holds terminals.
Why: herdr-core's holder (crates/herdr-core/src/holder.rs) showed a small process with no policy rarely needs replacing, so it survives daemon crashes and updates alike.
Rejected: handing the PTY descriptors to the new daemon over `SCM_RIGHTS` (herdr's handoff), which covers planned restarts but not crashes.

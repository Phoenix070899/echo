# An agent started from inside Kiro does not inherit its session markers, but keeps the human's KIRO_ settings

Decided: 2026-11-13
Status: accepted

The environment the daemon gives an agent drops the variables that name a running Kiro: `KIRO_SESSION_ID`, `KIRO_TURN_MARKER_DIR`, `KIRO_TUI_READY_*`, `KIRO_CHAT_CLI_*` and `KIRO_KAS_*`, with the Claude markers it already drops (`is_agent_var`).
Every other `KIRO_*` stays: `KIRO_HOME`, `KIRO_API_KEY`, `KIRO_LOG_LEVEL`, `KIRO_TELEMETRY_*`.
Why: a Kiro started from inside another Kiro would read the first one's session, ready file and binaries; `KIRO_HOME` is where the daemon writes the agent files and where Kiro must look for them, and the rest is the human's own configuration.
Rejected: dropping every `KIRO_*`, which would send a started Kiro to a different home than the one holding its agent file.

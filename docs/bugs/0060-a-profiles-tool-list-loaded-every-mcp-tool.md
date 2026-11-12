# A Profile's tool list made every Worker load every MCP tool in full

Found: 2026-10-31
Where: crates/hub/src/cli.rs (claude: --tools)
Fixed in: this change

Every Worker started with about 110k tokens of context, against about 18k for the same session started by hand, and re-read them on every turn: cache reads were 65% of all token cost over two weeks (668 Workers).
Cause: a Profile's `tools:` became `--tools Bash,Read,...` without `ToolSearch`, which turns off Claude Code's on-demand tool loading, so all 136 claude.ai connector tools (Gmail, Slack, Calendar, Drive) were sent in full on every request.
Fix: `--tools` always includes `ToolSearch`; measured in an interactive session, 160 tools and 104k tokens at the first turn became 9 tools and 18k.
Lesson: measure a Worker's real first request (the transcript's `api-request-shape`) after changing its launch flags; a flag that narrows tools can widen the context.

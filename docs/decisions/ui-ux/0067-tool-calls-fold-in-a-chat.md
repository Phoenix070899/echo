# Tool calls in a chat fold to one row, and runs of them to one group

Decided: 2026-11-12
Status: accepted

A tool call is one row: a chevron, the tool's name, and its target (the command's first line, the file, the pattern, the subagent's description).
Tool calls in a row fold into "N tool calls" with the tools' names; one call alone is its own row.
Opening a row shows the command or subagent prompt, an edit's removed and added lines in the Changes column's colours, and the first 40 lines of output; a failed call shows a red mark.
Thinking blocks and subagents' own turns are not shown.
Why: it reads like the Orchestrator mod's folded tool rows the human already knows, and keeps replies, the content the human reads, in front.

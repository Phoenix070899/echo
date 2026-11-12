# The title bar shows the context a Worker starts with, and its ••• opens the week's statistics

Decided: 2026-10-31
Status: accepted

Supersedes: ui-ux/0002's centred 520 pt search field: it now sits between the left and right sides and narrows (to 220 pt at least) when the right side needs room, so nothing covers it; its other rules stand.
After the plan usage, the bar shows "Worker start" and the median context a Worker started with over the last 7 days (`echoctl stats`), then a ••• button.
The ••• button opens a popover with the week's statistics: start context, context per turn, the token cost split, cold starts, reads and searches per Worker, repeated reads, and a row per Profile.
Echo reads them in the background at launch and every 30 minutes, because reading every transcript takes seconds; until the first read ends, or with no transcripts, the item does not show.
Why: the human wants to watch the numbers that cost tokens without running a command, and Worker start context is the one the ToolSearch fix (bugs/0060) should bring down.

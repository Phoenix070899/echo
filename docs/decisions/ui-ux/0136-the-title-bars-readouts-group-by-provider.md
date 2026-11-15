# The title bar's readouts group by provider, and fold as the window narrows

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0056, only that "Worker start" is its own item after the usage; ui-ux/0097, only that each limit shows its own name; ui-ux/0110, only the readouts' order (Workers running first). Their other rules stand.
The readouts are three groups, each a muted label and its figures in ink: CLAUDE with Session and Week as "19% 2H 5M · 12% 5D 13H", KIRO with its credits as "57% 15D 14H", and WORKERS as the running count, "·", the median start context, then the ••• button.
A limit's name moves to the usage tooltip, which still has one line per limit; a click on CLAUDE or KIRO still re-reads both.
As the window narrows, the readouts first drop every reset time, then fold the Workers group into its ••• button alone; the search field gives up room down to its 220 pt before either, and its placeholder shortens to "Search" rather than cut a word.
Why: the human found five readouts in a row hard to scan and saw the bar crowd the search field in a smaller window.
Rejected: one LIMITS group, which mixes a Claude limit with Kiro's credits under one name; one usage chip with a popover, which hides the figures the human watches.

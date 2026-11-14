# The chat's parts wear Foundry: square bubble, ruled tool rows, a callout for prompts

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0066, only the amber edge of a reply that needs the human, which is now the accent.
The human's bubble is the sunk grey, 12 by 16 pt in, at most 560 pt wide; replies are 15 pt, their headings the sans in bold (an h3 18 pt).
A tool call or a run of them is a 40 pt row in a 1 pt rule: the tool's mark, its name or "N tool calls" in semibold, the target or the tools in 12 pt mono, a chevron.
A divider's label and "ESC TO INTERRUPT" are mono labels; the working row sits on a 1 pt rule with an accent spinner, the step in ink and its timer in mono.
An agent's own permission prompt or question is Foundry's callout: the accent's soft fill in a 2 pt accent frame, a mono label, the command in mono on the sheet, then Approve and Deny.
The message box keeps its 2 pt ink frame; attach is a 28 pt square in a 1 pt rule, the model a mono label, and send a 28 pt ink square casting a 2 pt accent block.
An empty panel says so with a mono label over one quiet line.
The column stays at most 1200 pt (ui-ux/0078).
Why: the Main artboard.

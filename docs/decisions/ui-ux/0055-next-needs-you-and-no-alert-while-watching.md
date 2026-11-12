# ⌘J shows the next Need, and a Worker settling on screen posts no notification

Decided: 2026-10-31
Status: accepted

Supersedes: ui-ux/0008's list of taken shortcuts, which gains ⌘J; and features/0041's "When a Worker Echo saw running settles", which now skips the Worker on screen; their other rules stand.
⌘J (Session, Next Needs You) shows the Need after the one on screen, in the ledger's order: repo tab by repo tab, each agent group's Needs in turn, then any that belong to no agent; it wraps, and starts at the first when none is on screen.
A Worker that settles while Echo is the active app and that Worker is selected posts no notification; the human saw it settle, and its report already reads as read (ui-ux/0009).
Needs always notify, on screen or not, because one waits on the human.
Why: herdr-app alerts on finish only when the human is not looking and steps through agents most urgent first; Echo had neither.

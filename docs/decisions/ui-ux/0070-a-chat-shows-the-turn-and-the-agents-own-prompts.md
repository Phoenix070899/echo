# A chat shows its running turn as a last row, and its own prompts above the box

Decided: 2026-11-12
Status: accepted

While a turn runs, the chat's last row is a Working row: a spinner, the step the screen shows (the last `⏺` line, else the spinner's word), the spinner's time and tokens, and "Esc to interrupt".
It is the last row of the list, not part of the box, so the bottom anchor keeps the newest message in sight as it comes and goes.
The agent's own Needs (its permission prompts) show above the box as the same cards as Needs you; deciding one in either place settles both, since both call the same `decide`.
A prompt the daemon sees on screen without a Need says to answer it in the terminal (⇧⌘T).
Why: the transcript has no live state, so what the agent is doing now comes from its screen, as the ledger's does.

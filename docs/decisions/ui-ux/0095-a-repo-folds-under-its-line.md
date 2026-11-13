# A repo folds under its line

Decided: 2026-11-13
Status: accepted

Each repo line in the sidebar ends in a chevron that folds the repo: its agents and Workers hide, and only the line stays. The chevron points right when folded and down when open, and shows whenever the repo has an agent.
Folded, the repo line shows the total of what waits on the human across its agents, since their own counts (ui-ux/0094) are hidden; open, it shows none.
The fold is kept for the session only, like an agent's fold. Clicking the repo's name still shows the repo and does not change the fold.
Why: the human keeps several repos in the sidebar and wants the ones not in use out of the way.

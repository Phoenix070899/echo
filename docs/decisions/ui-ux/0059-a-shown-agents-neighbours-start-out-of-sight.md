# A shown agent's neighbours start their terminals out of sight

Decided: 2026-11-02
Status: accepted

Supersedes: ui-ux/0058's "Rejected for now: prewarming the agents next to the selected one"; the rest of 0058 stands.
Half a second after an agent shows, the agents just above and below it in the repo's ledger start their terminals out of sight, as a resting pointer does (ui-ux/0058), so ⌘ and a neighbour's number, or stepping through agents, shows its terminal at once.
A newer switch within that half second cancels the earlier one's, so stepping quickly through agents starts nothing in between.
Each kept terminal holds a multiplexer client, and at most 12 are kept (ui-ux/0050), so this adds at most two.
Why: the human switches agents by keyboard as often as by pointer; Orca does the same for the worktrees next to the active one.

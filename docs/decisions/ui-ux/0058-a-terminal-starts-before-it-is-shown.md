# A terminal starts at once at a known size, and resting the pointer on a row starts it before the click

Decided: 2026-11-02
Status: accepted

Supersedes: ui-ux/0028's and ui-ux/0029's "a pane starts only after its first layout settles" for sizes a pane has settled at before; a new size still waits the 0.1 s.
A new terminal whose pane already has a size an earlier pane settled at starts right away: every terminal in the panel has one size (ui-ux/0051), so that size is the real one, not a first guess.
Resting the pointer on an agent's or a Worker's row in the ledger or the rail for 120 ms starts its terminal out of sight, at the last settled size, and keeps it with the other kept terminals (ui-ux/0050), so a click on the row shows it already drawn.
A terminal started out of sight takes the main screen's scale, so it shows without a resize.
Nothing is started for a target already kept or shown, or before any terminal has shown.
Why: a first visit to an agent took about 330 ms before its terminal attached, a third of it the settle wait; measured on a test copy, it now takes about 70 to 110 ms, and a prewarmed one about 10 ms, like a kept one.
Rejected for now: prewarming the agents next to the selected one for ⌘1 to ⌘9, as Orca does for its neighbours; each kept terminal holds a multiplexer client.

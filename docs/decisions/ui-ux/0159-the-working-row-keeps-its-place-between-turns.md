# The Working row keeps its place while no turn runs

Decided: 2026-11-17
Status: accepted

The chat's Working row (ui-ux/0070) is always laid out as its last row while the agent is live; when no turn runs it is hidden, not removed.
A settled Worker's chat still drops it, since its turn is over for good.
Why: the screen flicks between working and idle while the agent thinks, so a row that came and went moved every message above it up and down.

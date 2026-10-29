# A terminal stays alive out of sight, so switching back is instant

Decided: 2026-10-29
Status: accepted

Adds to ui-ux/0029 and features/0018: a pane no longer ends its Ghostty surface when it shows another agent or Worker.
The surface leaves the window still running, kept by `TerminalCache` in `TerminalPane.swift`, and showing its target again puts the same surface back, already drawn.
Before, every switch started a new surface, a login shell, and a multiplexer attach, and the multiplexer redrew the screen from scratch; that was the delay.
A kept surface draws nothing while out of sight (it is occluded), and one whose process exits is let go.
At most 12 are kept, each a multiplexer client or `echoctl attach`; past that, the one shown longest ago ends.
A kept surface is reused only for the same target, command, and agent state: an agent that stopped or started gets a new one, so a plain attach still reaches whatever runs now.
Why: the human saw the terminal lag each time they switched Orchestrators.

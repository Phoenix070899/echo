# Each checkout has its own side terminal under the Files column

Decided: 2026-11-12
Status: accepted

A bar labelled Terminal sits at the foot of the Files column and is always there; opening it shows a shell in the shown checkout's folder below the bar, with a draggable edge above it (default 240 pt, double-click resets it).
The shell is the human's own, not the agent's: it is keyed by the checkout path, so each checkout has one, and it never shares a size or the keyboard with the agent's terminal.
Hiding the section only stops drawing it; the shell and any command in it keep running, and the bar shows a turning mark and "running" while the shell prints.
The keyboard goes to the shell only when it is clicked or opened with ⌃` (Terminal menu, or the button in the Files header); selecting an agent, or focusing the Files tree, takes it back.
An End button on the bar stops the shell; typing `exit` ends it too, and a new one starts in its place.
Opening the section widens the Files column to at least 340 pt.
Why: the human wanted a command line next to the files without opening the agent's terminal, and output that streams while hidden.
Rejected: sharing the agent's shell (two views fight over its size), and a full-width bottom panel (it takes the chat's height).

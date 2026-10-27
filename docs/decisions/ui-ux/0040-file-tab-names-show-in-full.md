# File tab names show in full, and the strip scrolls sideways

Decided: 2026-10-24
Status: accepted

Each tab in the strip over the main panel shows its whole name on one line, never wrapped or cut short.
When the tabs are wider than the strip, the tabs scroll sideways (trackpad, or Shift with the wheel), with no scroll bar, while "Esc returns to the terminal" stays put on the right.
The tab shown is scrolled into view whenever it changes, so opening a file or pressing a tab key never leaves its tab off screen.
Why: the human could not tell open files apart when long names were clipped.

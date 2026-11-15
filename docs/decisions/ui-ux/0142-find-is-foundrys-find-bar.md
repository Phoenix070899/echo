# ⌘F in a file or a terminal opens Foundry's find bar

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0038, only that ⌘F opens the system find bar; its keys and the rules on rendered files stand.
⌘F opens `FoundryFindBar` at the view's top right: a square field in a 2 pt frame, in mono, with "3 of 14" or "No matches" beside the text.
In a file, every match takes the highlighter's wash and the current one the highlighter, scrolled to; it starts at the first match after the caret, and text picked on one line fills the field.
Return and ⌘G go to the next match, Shift-Return and ⇧⌘G to the one before; Esc closes the bar first and gives the keyboard back to the file.
Over a terminal the same bar wears the terminal theme's colours, and the terminal still finds and marks the matches.
Why: the system's find bar is a rounded strip of stock controls across the top of the file.

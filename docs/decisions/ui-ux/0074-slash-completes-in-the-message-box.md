# A slash in the message box completes Claude Code's commands

Decided: 2026-11-12
Status: accepted

Typing `/` as the first character lists up to eight commands: names starting with what follows the slash first, then names containing it; a space ends the list.
Up and Down move the highlight, Tab or Return completes the name, Return again sends, and Esc clears the draft.
A command that opens a menu Echo cannot draw (`/model`, `/config`, …) is sent, then the terminal shows for it; the chat stays the view for every other command.
Why: slash commands are most of what the terminal gave that a plain box would lose; completing them keeps them a keystroke away.
Rejected: drawing the menus in the chat, which would copy Claude Code's own pickers and drift from them.

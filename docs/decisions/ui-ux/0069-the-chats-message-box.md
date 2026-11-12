# One message box under the chats: Return sends, Shift-Return adds a line, Esc interrupts

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0066, only its read-only footer; the chat takes typing now.
Under the chat sits one message box for every kept chat; each agent keeps its own unsent draft (`AppModel.composer`).
Showing a chat, or selecting its agent again, gives the box the keyboard.
Return sends, Shift-Return adds a line, and Esc while the agent works interrupts it; any other key, such as Ctrl-C, goes to the agent only in its terminal view.
Sending clears the box at once; the message appears when the transcript has it, and a refused send puts the text back with the daemon's reason in red under the box.
A stopped agent shows no box, only a line saying to start it, with its shell in the terminal view.
Why: one field that stays focused across switches; a field per chat made each switch focus a new field, which cost AppKit a key-view walk (bugs/0068).

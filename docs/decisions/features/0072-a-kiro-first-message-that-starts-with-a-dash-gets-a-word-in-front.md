# A Kiro first message that starts with a dash is sent as "Message: <text>"

Decided: 2026-11-13
Status: accepted

The first message of a Kiro start goes last on the command line as the positional input. When it starts with `-`, the adapter sends `Message: ` in front of it.
Unguarded, Kiro reads the text as an option (`-d <id>` deletes a session). `--` before it works headless but, in the interactive TUI, the message is lost.
A plain word survives Kiro's trimming and is harmless to the agent; a message without a leading dash is sent as typed.
Why: a first message can begin with a dash, and the start must never run a Kiro option the human did not ask for.
Rejected: `--` before the message, which loses it in the TUI.

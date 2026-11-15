# A message sent from the chat shows at once, dimmed, until the transcript has it

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0069, only that the message appears when the transcript has it, because the human saw nearly a second pass between sending and seeing it.
Sending clears the box and puts the message in its bubble under the chat at once, at 60 % opacity, fading in as a new row does (ui-ux/0133); the first message in an empty chat shows without a fade.
When the transcript brings a message the human typed, it takes the place of the oldest dimmed one in one step, so nothing moves; a new session clears them, and a refused send removes its own and puts the text back as before.
A slash command shows only from the transcript, since it may never write a message.
Why: Claude Code writes the message to its transcript only after Echo has typed it (150 ms) and Claude Code has taken it in, its prompt hooks included, which with the held read (features/0088) is still most of a second.

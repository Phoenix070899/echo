# A message sent from the chat took most of a second to show

Found: 2026-11-15
Where: app/Sources/HubApp/ChatView.swift (`ChatBottom.send`, `ChatFeed`)
Fixed in: the change that adds this file

The human sent a message from the chat and saw it in the conversation nearly a second later.
Cause: the chat drew only what the transcript held, and the message reaches the transcript after the daemon types it (150 ms before Enter) and Claude Code takes it in, its UserPromptSubmit hooks included; the held read (features/0088) only removed Echo's own poll from that wait.
Fix: the sent message shows at once, dimmed, and the transcript's copy replaces it (ui-ux/0137).
Lesson: what the human did shows the moment they do it; a view drawn from a slower source shows the action locally until that source catches up.

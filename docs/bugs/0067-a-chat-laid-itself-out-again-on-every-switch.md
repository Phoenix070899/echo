# A chat laid itself out again on every switch, and redrew on every poll

Found: 2026-11-12
Where: app/Sources/HubApp/ChatView.swift, AppModel chat feeds
Fixed in: the change that adds this file

`measure-switch.sh` with three Orchestrator chats of a real 2.4 MB transcript: 153 ms a switch against 24 ms for terminals, and 229 busy ms in 9 idle seconds against 16.
Cause: each switch made a new `ChatView` and `ChatFeed`, so the LazyVStack measured every reply's text again from the bottom; and every 0.8 s poll set a `@Published` flag, redrawing the chat with nothing new.
Fix: the model keeps each agent's `ChatFeed`, `ChatDeck` keeps the last six chats laid out out of sight (ui-ux/0068), and a poll publishes only when the rows change.
Lesson: a view that shows a long list per selection is kept alive across selections like the terminals, and a timer never writes a `@Published` value it did not change; measure with `measure-switch.sh` before calling it done.

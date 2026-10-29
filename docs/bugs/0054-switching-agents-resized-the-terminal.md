# Switching between agents resized the terminal, so it redrew slowly

Found: 2026-10-29
Where: app/Sources/HubApp/ContentView.swift (MainPanel), app/Sources/HubApp/TerminalPane.swift (TerminalCache)
Fixed in: this change

Showing an Orchestrator after a Terminal in the repo's checkout, or after 2 or 3 switches between Orchestrators, the terminal was slow to show, even with ui-ux/0050's kept terminals.
Cause: the file tab strip showed only for a checkout with open files, so those terminals were 2 rows shorter (99x35 against 99x37 in tmux); each switch between them resized the terminal, and the multiplexer and Claude Code redrew everything.
Fix: the strip always shows over a terminal (ui-ux/0051), so every terminal in the panel has one size.
Lesson: anything shown over a terminal must not change its size between targets; check `tmux list-clients -F '#{client_width}x#{client_height}'` when switching feels slow.

# The Working row shifted the chat while the agent thought

Found: 2026-11-17
Where: app/Sources/HubApp/ChatView.swift (`WorkingRow`)
Fixed in: the change that adds this file

While an agent thought, the "Esc to interrupt" row at the bottom of its chat showed and hid many times a second, and the messages above it jumped up and down with it.
Cause: the row was drawn only while the screen read as working, and Claude Code's screen flicks between its spinner and an idle look mid-turn.
Fix: when no turn runs the row is drawn hidden, so its height stays (ui-ux/0159).
Lesson: a row driven by screen state that can flicker must keep its space; show and hide its content, not its frame.

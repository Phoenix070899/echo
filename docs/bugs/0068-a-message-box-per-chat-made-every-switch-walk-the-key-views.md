# A message box per chat made every switch focus a new field and walk AppKit's key views

Found: 2026-11-12
Where: app/Sources/HubApp/ChatView.swift (ChatBottom)
Fixed in: the change that adds this file

`measure-switch.sh` with chats went from 22 ms a switch to 80 to 95 ms once each kept chat had its own message box.
Cause: each switch focused the shown chat's own text field; AppKit's password AutoFill check then computed the key-view loop (`_NSComputeFirstKeyViewVisuallyInDirection`) on every focus.
Fix: one message box under all kept chats, bound to the shown agent's draft, so the same field stays focused across switches.
Lesson: a view kept per agent holds no text field; keep one field and swap what it edits, and measure switching after adding anything focusable.

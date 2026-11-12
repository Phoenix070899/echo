# Earlier messages load when the chat is scrolled to its top

Decided: 2026-11-12
Status: accepted

The chat opens on its last 200 messages; scrolling up to its top loads the page before, and the "Show earlier messages" button does the same.
The page arrives above the message that was first, which stays where it was, so reading is not moved.
When the session was renewed or cleared, the page before it ends with a "Session renewed, context cleared" divider, in the same history.
Why: a long chat should open at once and still reach back to the start.
Rejected: loading the whole transcript, which costs time on every switch.

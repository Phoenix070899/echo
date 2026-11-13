# A failed Kiro turn showed its error twice when a poll fell between its two lines

Found: 2026-11-13
Where: crates/hub/src/kiro_chat.rs (`Lines`), crates/hub/src/chat.rs (`read_with`, `parse_range`)
Fixed in: the change that adds this file

Found by review of the Kiro parity work. A failed turn writes a `displayError` line and, a few lines later, a `turn_end` with `stopReason: error`. When the chat read ended between them, it showed Kiro's message, and the next read added "Error: the turn failed." below it. A tail read whose first window began between the two lines showed only the generic line.
Cause: the reader remembered that the message was shown only within one range of lines, and every read parses a new range. The app appends the items of an `after` read as they come, so it cannot drop the second note; the daemon is where the output has to be the same for any range.
Fix: the line that ends a failed turn is a generic note only when no `displayError` of its execution lies between it and the turn's start, looked for in the file itself, up to 64 KiB before the line. `read_with` gives its parser each line's offset for that. The same file now gives the same notes whether read whole, by `after`, or from the tail by `before`.
Lesson: a reader that is called in ranges must not decide from what an earlier range showed; decide from the file around the line, or the output changes with where a poll or a page began.

# echoctl stats listed "worker list;" apart from "worker list" and printed a cost of "-0%"

Found: 2026-11-11
Where: crates/hub/src/stats.rs (command_key, percent)
Fixed in: the change that adds this file

The 14-day report had two "tool result" rows, `worker list` and `worker list;`, and a36's row read `-0%`.
Cause: a command word was cut off only at a word that starts with `;`, `&` or `|`, so `echoctl worker list; echoctl wait` kept the `;` on `list;`. And an empty f64 sum in Rust is -0.0, which rounds and prints as "-0".
Fix: separators are trimmed off the end of each command word, and a percent adds 0.0 so -0.0 becomes 0.
Lesson: when naming a shell command by its words, strip the separators a word can end with, not only those it can start with; and normalize -0.0 before printing a float that can be an empty sum.

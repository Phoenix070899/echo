# Kiro's credits read 28 for 29 percent, and read from the human's Kiro home when the scratch folder failed

Found: 2026-11-13
Where: crates/hub/src/kiro_usage.rs (`credits`, `scratch_home`, `read`), crates/hub/src/daemon.rs (`refresh_kiro_usage`, `Usage::finish_kiro`)
Fixed in: the change that adds this file

Found by review of the Kiro parity work. Two faults in the credits reader.
Percent: 580 of 2000 credits showed 28. Cause: `used / cap * 100.0` was floored, and the float product of 580 / 2000 * 100 falls just under 29. Fix: the percent is `used * 100.0 / cap` rounded to the nearest whole number (10 of 2000 is 1, 1990 is 100, 0 is 0). A zero or absent limit still gives no reading.
Home: when `<state>/kiro-home` could not be made, `scratch_home` gave `None` and the `kiro-cli acp` child ran without `KIRO_HOME`, in the human's `~/.kiro`, whose logs it then churned every five minutes. Decision features/0078 says it never falls back to that home. Fix: `scratch_home` returns the error, `read` takes the folder the scratch home goes under and runs no child when it cannot be made, writes one line to stderr, and answers `Outcome::Skipped`. The daemon treats it as a failed read: the last good value stays, no error is shown, and the next try comes sooner.
Lesson: a safety fallback an `Option` hides is no fallback: when a precondition of a child process fails, skip the run and say so, rather than letting the child inherit the environment it was meant to avoid. And compute a percent as `used * 100 / cap` before rounding, never through a ratio that floats can leave just below a whole number.

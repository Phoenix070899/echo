# Reading Claude Code's screen trusts only its bottom, never the transcript

Decided: 2026-10-31
Status: accepted

A trust or permission dialog is live only within the last 12 non-blank lines and while no input box (a `❯` line between two horizontal rules) sits below it; an answered prompt scrolls up with the input box back under it.
A spinner line means Working only in the six lines above the input box, or anywhere in those last 12 lines when no input box shows; "esc to interrupt" in the footer means Working too.
Ctrl+O's detailed transcript view reads as Working, so the old prompts it shows are never raised.
Why: the whole-screen match took a prompt or spinner quoted in the transcript for a live one; herdr's Claude rules (detect/manifests/claude.toml) scope each signal to a screen region the same way.
Rejected: the title spinner herdr reads, because Claude Code 2.1.308 keeps `✳` in its title while working (checked 2026-10-31).

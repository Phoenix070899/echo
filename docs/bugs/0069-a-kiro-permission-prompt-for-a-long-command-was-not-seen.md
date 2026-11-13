# A Kiro permission prompt for a long command never reached Needs you

Found: 2026-11-13
Where: crates/hub/src/screen.rs (`kiro_look`)
Fixed in: the change that adds this file

In the smoke run on real Kiro, an Orchestrator asked to run a 990 character `echo` command. Kiro showed its approval dialog, but Echo read the screen as Working: no `permission_prompt` in Needs you, and `decide` refused with "no permission prompt is waiting".
Cause: `kiro_look` counted a prompt as live only when its title line (`<what> requires approval`) was within the last 12 non-blank lines (`RECENT`). The command wraps over many lines at 160 columns, so with 7 lines of command the title sat 14 lines up. Commands of 6 or more wrapped lines, such as a long `git commit -m` or a heredoc, fell outside.
Fix: a title above that window still counts when the last line of the screen is the dialog's own key hint (`esc to close · ↑↓ to navigate ...`) and no input box sits below the title. A prompt quoted in the transcript is followed by the input box, so it stays not live.
Lesson: the window for a screen element must cover its longest legitimate size; when content can wrap without limit, anchor on the element's fixed footer instead of counting lines from its variable top.

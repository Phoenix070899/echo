# Claude Code's prompt bar was unreadable on a light terminal theme

Found: 2026-11-16
Where: app/Sources/HubCore/TerminalTheme.swift (`ghosttyConfig`)
Fixed in: the change that adds this file

On Foundry Light, Claude Code drew each sent prompt as ink on a grey bar (2.5:1), and its dim lines ("Ran 1 shell command", "Worked for 23s") read at 2.9:1.
Cause: the human's Claude Code theme is `dark-ansi`, which paints the bar in bright black and leaves the text at the terminal's default colour, dark on a light theme; Ghostty draws dim text at half opacity.
Fix: the terminal config sets `minimum-contrast = 3`, so text under 3:1 against its cell flips to black or white, and `faint-opacity = 0.7`, so dim text reads at about 5:1 on Foundry Light.
Lesson: a program in an agent's pane picks colours for the terminal it assumes, not the one Echo shows; guard readability in the terminal, not only in the palette.

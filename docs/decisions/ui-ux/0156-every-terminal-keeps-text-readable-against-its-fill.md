# Every terminal keeps text readable against its fill

Decided: 2026-11-16
Status: accepted

Every terminal Echo shows, on any theme, sets Ghostty's `minimum-contrast` to 3 by default, and dim text keeps 70 % of its colour by default, not half.
Text that would sit under 3:1 against its cell's colour is drawn black or white instead.
Settings' Terminal Theme sets both colours involved: Prompt bar is the palette's bright black, where Claude Code draws sent prompts, and Dim text is a slider from 30 % to 100 %.
Links is the palette's blue, where Claude Code draws links and file paths, and Contrast is a slider from Off (1) to 7:1.
Text on the bar has no colour of its own: it is the theme's Text, so Contrast is how the human keeps it readable.
Dim text and Contrast belong to the look, not the theme, so moving them leaves the preset as it is.
The default stays at 3, not 4.5, so low-contrast themes like Solarized keep their own colours.
Why: a program that assumes a dark terminal, like Claude Code's `dark-ansi` theme, made its prompt bar unreadable on Foundry Light (bugs/0093).

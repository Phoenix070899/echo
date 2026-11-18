# The terminal theme sets every colour, the palette included, and has no Match Orca

Decided: 2026-11-16
Status: accepted

Supersedes: ui-ux/0035, only Match Orca in the Theme tab; everything else in it stands.
Settings' Terminal Theme lists eleven presets: Ayu Dark, Tango Light, Hub Dark, Dracula, Nord, Gruvbox Dark, Catppuccin Mocha, Tokyo Night, One Dark, Solarized Dark, and Solarized Light.
Besides Background, Text, Cursor, and Selection it sets Cursor text, Selected text, and Bold; each of those three is Auto (left to the terminal) until a colour is picked, and Auto puts it back.
Each of the 16 palette colours is a swatch that opens the colour panel; its name and hex show in its tooltip.
Changing any colour makes the preset read Custom, as before.
The Match Orca row is gone; Echo's first look keeps its values (Ayu Dark, JetBrainsMono Nerd Font 14) under the name `standard`.
The daemon still strips `ORCA_` variables from what agents inherit (bugs/0005), so an Echo started inside Orca does not leak them.
Why: the human wanted more colours to set and nothing in Echo named after Orca.

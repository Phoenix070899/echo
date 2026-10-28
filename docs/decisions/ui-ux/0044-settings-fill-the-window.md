# Settings fill the window, opened from a gear at the ledger's foot or the menu's Settings…

Decided: 2026-10-28
Status: accepted

Supersedes: ui-ux/0035 and ui-ux/0043 on where Settings live: there is no Settings window and no tab toolbar; what each section holds stands.
A gear button at the foot of the ledger, beside the collapse button (above it on the collapsed rail), shows Settings in place of the ledger, the panel, and the Files column, below the title bar.
The menu's Settings… (⌘,) and Quick Open's Settings go to the same page, on the section last shown.
The page lists its sections on the left (Window, Terminal Theme, Background, Font, Multiplexer, Agents, Echo Remote) as flat full-width rows, the picked one on the selected fill with a run-colour bar; the picked section fills the right, under its name, at most 680 pt wide.
Done, Esc, ↑ and ↓ work from the keyboard; Done and Esc go back to the agents, which keep running meanwhile.
`echoctl ui settings [section]` shows a section the same way, without bringing Echo forward, so an agent can point the human at a setting only they change.
Why: the human wanted Settings as a full page reached from the sidebar, and a separate window's tabs no longer fit.

# Kiro's credits follow Claude's two limits in the usage bar, in the same style

Decided: 2026-11-13
Status: accepted

Supersedes: ui-ux/0002's "the plan usage" as Claude's alone; the bar's place and layout, and ui-ux/0090's rules, stand.
The usage item shows Claude's first two limits (Session, Week) exactly as before, then Kiro's credits when the daemon sends the "Kiro credits" entry (features/0078): the name, the used share in the same weight, red from 90 %, and the time left before the reset.
Kiro's entry is always last, whatever order the daemon lists, and it shows when Claude sent no limits; with none from the daemon, nothing is added.
The time left reads Kiro's "Dec 1" as that day's start in this Mac's time zone ("17d 12h"); Claude's "Oct 17 at 4:50pm" reads as before, and a reset the app cannot read shows no time.
The tooltip has one line per limit. Claude's read "Session: 48% used, resets Oct 17 at 4:50pm"; Kiro's reads "Kiro credits: 603.62 of 2000 credits, resets Dec 1", with no "resets" when Kiro gave no date. A click still re-reads both.
Claude's `error` keeps its rule: it shows ("Usage unavailable", and its text as the tooltip) only when Claude sent no limits, and a Kiro entry does not hide it; beside Kiro's entry the label reads "Claude usage unavailable", so it is not taken for Kiro's.
Why: the human watches what runs out, and an agent on Kiro spends credits, not Claude's limits; the same style keeps the bar one list.
Rejected: a second item or a popover for Kiro, which adds a control to a bar with no room to spare; showing Kiro's entry before Claude's, or dropping it past the second item, which hid it whenever Claude listed a third limit.

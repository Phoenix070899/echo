# The last six chats shown stay laid out out of sight

Decided: 2026-11-12
Status: accepted

`ChatDeck` keeps the chats of the last six agents shown in one ZStack and shows the selected one; the others stay laid out, hidden and out of hit testing.
Each agent's chat items (`ChatFeed`) are kept while Echo runs, so showing an agent again reads only new transcript lines.
Only the chat in sight reads new lines, every 0.8 s; a read with nothing new publishes nothing.
Why: laying a long chat out again on every switch took 153 ms a switch against the terminal's 24 ms (bugs/0067); kept chats switch in 22 ms, as terminals do (ui-ux/0050).

# The window's columns stay an HStack; a switch's layout cost is inside the columns

Decided: 2026-11-02
Status: accepted

The ledger, the main panel, and the Files column stay in an `HStack`.
Tried and dropped: a custom `Layout` that gave each column its width and the full height without asking it what size it wants, to save the `HStack`'s measuring passes that `sample` showed on every switch.
The time only moved into the new layout's placing of its columns, about 200 samples in 30 switches either way, because laying out a column lays out what it holds; switches took 40 and 20 ms with Files shown and hidden, the same as before (`app/scripts/measure-switch.sh`).
What a switch lays out is what changed: the new checkout's file list, the panel's header and terminal, and the ledger's highlight.
Why: no gain, and one more layout type to keep; with ui-ux/0061, cutting more would mean drawing the file list in AppKit.

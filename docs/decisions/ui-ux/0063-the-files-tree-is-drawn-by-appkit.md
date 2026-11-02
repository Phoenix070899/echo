# The Files column's tree is drawn by AppKit, looking as the SwiftUI rows did

Decided: 2026-11-02
Status: accepted

The Files tab's tree is one AppKit view (`FileList`, in `FileList.swift`) that draws only the rows on screen; it was a SwiftUI `LazyVStack` of row views.
It looks as the SwiftUI rows did, checked pixel by pixel on a 2x screen in the dark look: the same text, at the same places; the same rounded fills for the cursor and the pointer; and icons that SwiftUI itself renders once per colour and the list draws, within a tenth of a pixel of where the rows had them.
`FilesTree` keeps the keys, the keyboard focus, the cursor, and the type-to-select of ui-ux/0018; the list draws, scrolls the cursor into view, and reports clicks, which act on release as before.
It keeps the row's menu, dragging a file out, the path as a tooltip, and an accessibility element for each row.
Opening or closing a folder shows its rows at once, without the 0.12 s fade the SwiftUI rows had.
Why: showing another checkout laid out a SwiftUI view for every row on screen; with the Files column shown, a switch fell from 35 to 40 ms to about 28 ms (`FILES=1 app/scripts/measure-switch.sh`), close to the 26 ms with it hidden.
The Changes and Commits tabs and file search stay SwiftUI.

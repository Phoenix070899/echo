# Chat text is one selectable view per run of blocks, with a pointer on links and a copy on release

Decided: 2026-11-12
Status: accepted

Chat replies, the Final Report body and the user's message are drawn by an AppKit text view (`ChatText`), one per run of Markdown blocks, instead of one SwiftUI `Text` per block.
Why: SwiftUI `Text` selects inside a single block only, and shows no pointer over links. A drag from one paragraph to a list item selected nothing.

- A drag selects across paragraphs, headings, lists, quotes and code in the run, and the plain text is copied to the clipboard when the mouse is released. A click without a drag copies nothing.
- Links (Markdown links and bare `http(s)` addresses) show a pointing hand and open in the default browser. A name such as README.md is not a link, and inline code is never linked.
- Only one selection exists at a time; selecting in another reply clears the first.
- Tables, rules and front matter stay SwiftUI, so a selection stops at them.
- The view redraws only when its content, size or colours change, so a selection survives the chat's refresh.
- Spacing, markers and sizes match the SwiftUI blocks (`MarkdownBlockView`); a user message still hugs its longest line.

Tool cards and file chips are still SwiftUI `Text` and are not covered.

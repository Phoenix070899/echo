# Inline code chips were taller on a wrapped line than on a paragraph's last line

Found: 2026-11-15
Where: app/Sources/HubApp/ChatText.swift (`ChatTextBuilder.inline`, `EchoTextView.drawDecorations`)
Fixed in: the change that adds this file

In a chat reply, `in` on the first line of a paragraph sat in a taller chip than `in` on its last line.
Cause: the chip was the text's `.backgroundColor`, which AppKit fills over the whole line fragment, and a wrapped line's fragment includes the paragraph's line spacing while the last line's does not.
Fix: inline code carries only `.echoInlineCode`, and the view draws each chip itself: the span's width plus 3 pt a side, and the code font's ascender to descender plus 2 pt around the baseline, on every line; 5 pt of kerning on the characters either side keeps the chip clear of the text next to it.
Lesson: a fill that must look the same on every line is drawn from the font's metrics, never from `.backgroundColor` on text with line spacing.

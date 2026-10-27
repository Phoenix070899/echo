# ⌘F finds in the previewed file

Decided: 2026-10-24
Status: accepted
Supersedes: ui-ux/0018's list of taken shortcuts, which this extends; its rules still hold.

With the keyboard in a file preview, ⌘F opens the system find bar over the file: every match is marked, ⌘G and ⇧⌘G go to the next and previous one, and Esc closes the bar before it closes the preview.
Rendered Markdown and HTML switch to their source first, since only the source is text to find in; images and PDFs take no ⌘F.
⌘F, ⌘G, and ⇧⌘G belong to the preview only while it holds the keyboard; elsewhere they stay the terminal's own search keys, so no menu item takes them.
Why: the human wanted to search inside one file, not only across the checkout.

# Settings shows the Preferences and each repo's Lessons, line by line

Decided: 2026-10-28
Status: accepted

Settings has a Preferences and Lessons section, after Agents.
Preferences show under their `## ` headings; Lessons show for one repo picked from a menu, with how many there are against the 60 before an `ino` Worker merges them.
Each line has a delete button that shows on hover; a field at the end adds a dated line (a Preference under the heading picked, a Lesson signed "you"); Open in Editor opens the file.
Echo reads the files fresh each time the section shows, since Workers and `ino` write them too, and removes a line only when it is still written as shown.
`echoctl ui settings memory` shows this section.
Why: the human wanted to see and correct what agents keep between Tasks without opening files.

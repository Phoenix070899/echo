# What Echo asks before acting is a Foundry card in the window

Decided: 2026-11-15
Status: accepted

Every question Echo asks (save or drop a file's edits, close an agent, stop a Worker, keep a try, delete a Team, remove Members, name a custom Worker, make a new pairing link) is `FoundryAsk`, never an alert or a confirmation dialog.
It is a 420 pt card centred over the window dimmed 28 % (ui-ux/0006): the sheet grey in a 2 pt ink frame with no shadow, a bold question over one quiet line, an optional field, then Cancel and the answers.
The last answer is the primary button and Return runs it; Esc, Cancel or a click on the backdrop cancels; a destructive answer is in the failed red, filled when it is the primary.
While a question is up the terminal lets go of the keyboard (`AppModel.asking`), and the keyboard goes back to what held it before once the card closes.
Quitting with unsaved edits opens the window and asks there, one file at a time.
Why: an alert is a separate rounded system window that wears none of Foundry.
Rejected: keeping `NSAlert` for questions asked from model code, which would leave two looks for the same kind of question.

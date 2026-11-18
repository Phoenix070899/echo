# Profiles are drafted and changed with an agent in place

Decided: 2026-11-16
Status: accepted

Builds on ui-ux/0145, ui-ux/0146 and ui-ux/0149; follows features/0101.
New Profile asks the name and level, then "What should <name> do?" with a field, Start blank and Draft with agent; the file is written blank at once as before, then the draft fills the form, with the role open in its text field.
Under the role, "Change with an agent" holds a field for what to change, a "Drafts with" CLI picker listing only signed-in CLIs, a model picker of that CLI's models, and Ask agent (⌘Return).
The pick is remembered on this Mac and starts as Claude Code with Sonnet 5.5; New Profile drafts with it and names it in its message.
While a draft runs, the Profile's fields, the pickers and Save are disabled, and a spinner with "Drafting with <agent>…" and Cancel stands in for Ask agent.
Once it lands, the changed fields carry their Changed mark, the field clears, and a line gives the agent's summary and what Echo left out, with Undo, which puts the form back as it was before that draft; Revert still goes back to the file.
Picking another Profile cancels a running draft.
Echo's own Profiles show no agent box until Make my copy.
Why: the human describes what they need instead of filling every field, and sees and reviews each change before it is saved.
Rejected: two pickers in the New Profile card, which crowds it; saving the draft at once, which skips the review.

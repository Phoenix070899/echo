# The ledger is a tree of one-line rows, and a Worker that finished leaves it

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0052 (a Worker's row has no second line any more), ui-ux/0009 (there is no Done list, so no unread dot or Clear), and the repo tab strip and the Needs you, Running and Done sections of the ledger.
The ledger is a tree: a line per repo (a tray icon, its name, an amber count of what waits on the human), under it an indent guide beside a line per agent (its mark and name, a hollow dot when stopped), and under each agent a line per Worker (its mark and its title, nothing else).
Every line is 30 pt tall with a rounded fill when picked or hovered; the id, profile, branch, age and status words move to the row's tooltip.
Every repo with a live agent or Workers at work shows at once; the rest fold into a Stopped line at the foot. The + beside the Sessions label starts a session.
A Worker is listed while it works, while it waits on you (an amber mark, with its question or prompt as buttons under its agent), and after it ended badly (red, until Dismiss). One that finished with a Final Report, or ended at its input box, leaves the tree at once; the one open in the main panel stays until the human shows something else, so a notification still opens its report.
The daemon keeps its Workers and its five-minute window (features/0030) unchanged: notifications and Echo Remote still fire when a Worker settles; only the tree stops listing it.
An agent's Workers fold under its chevron; ⌘1 to ⌘9 still show the first nine agents of the repo, the number now in the tooltip.
Why: the human wanted a quiet sidebar like a chat app's, with a finished Worker gone instead of waiting to be cleared.
Rejected: dropping done rows in the daemon, which would stop the notification and the phone alert that fire on a Worker settling.

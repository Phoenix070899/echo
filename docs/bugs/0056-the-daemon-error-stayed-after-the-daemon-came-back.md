# "Cannot reach the Hub Daemon" stayed after the daemon came back

Found: 2026-10-29
Where: app/Sources/HubApp/AppModel.swift (background, refreshSessions, follow)
Fixed in: this change

After the daemon went down and a new one started, the red "cannot reach the Hub Daemon: Connection refused" banner stayed, though the ledger worked again.
Cause: an action that failed while the daemon was down set the window's error, and only another action that succeeded, or the banner's ✕, cleared it; reaching the daemon again cleared `daemonDown` but not the error.
Fix: an error that only says the daemon could not be reached (`HubError.connect` or `.closed`) is cleared as soon as the session list or a repo's events reach the daemon again.
Lesson: an error that describes a passing state must clear itself when the state passes.

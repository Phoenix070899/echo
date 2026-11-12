# Workers of a repo with no Orchestrator were not listed in the ledger

Found: 2026-10-31
Where: app/Sources/HubCore/Models.swift (Snapshot.groups), app/Sources/HubApp/ContentView.swift (agent group body)
Fixed in: this change

In a repo whose only agent was a Claude Code session, Workers started with `echoctl worker start` counted in the repo's badge but showed nowhere: neither their Needs nor their Running or Done rows.
Cause: a Worker with no agent belongs to the first Orchestrator, and with none it belonged to no group; and a group drew Running and Done only under an Orchestrator.
Fix: such Workers fall to the first agent of any kind, and a Claude Code session's group lists Running and Done whenever it has Workers.
Lesson: every count the human sees must match rows they can find; check a fallback owner for the case where the usual owner does not exist.

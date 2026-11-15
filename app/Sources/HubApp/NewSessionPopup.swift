import Foundry
import HubCore
import SwiftUI

/// Echo's own New session menu, opened under the ledger's New session button (ui-ux/0113) in
/// Foundry's popover (ui-ux/0125): an Orchestrator and a Terminal, each with what it does and its
/// shortcut, and a way to start in another repo. ↑ ↓ pick, Return starts, Esc or a click outside
/// closes. Fan Out a Task stays in the File menu and Quick open.
struct NewSessionPopup: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        FoundryMenu(
            label: "New session",
            head: repoName.map { "Start in \($0)" } ?? "New session",
            detail: branch,
            entries: [
                .item("Orchestrator", note: "Hands Tasks to Workers and reports back", key: "⌘N",
                      icon: AnyView(AgentGlyph(kind: .orchestrator, size: 16))) {
                    model.showNewSession(repo: model.selectedRepo, kind: .orchestrator)
                },
                .item("Terminal", note: "A plain shell in the repo, in your multiplexer", key: "⇧⌘N",
                      icon: AnyView(AgentGlyph(kind: .terminal, size: 16)), enabled: model.selectedRepo != nil) {
                    model.openTerminal()
                },
            ],
            foot: AnyView(AnotherRepo()))
    }

    private var repoName: String? {
        model.selectedRepo.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// The branch the selected agent or Worker is on, when Echo knows it.
    private var branch: String? {
        switch model.selection {
        case .agent(let repo, let id)?:
            let agent = model.agents(repo).first { $0.id == id }
            return agent?.head ?? agent?.branch
        case .worker(let repo, let id)?:
            return model.snapshot(repo).workers.first { $0.id == id }?.branch
        case nil:
            return nil
        }
    }
}

/// The menu's foot: "In another repo? Choose a repo…".
private struct AnotherRepo: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.foundryPopoverClose) private var close

    var body: some View {
        HStack(spacing: 4) {
            Text("In another repo?")
            Button("Choose a repo…") {
                close()
                model.showNewSession(repo: nil, kind: .orchestrator)
            }
            .buttonStyle(.ledgerLink)
        }
    }
}

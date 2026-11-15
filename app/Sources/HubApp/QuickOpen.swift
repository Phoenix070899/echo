import Foundry
import HubCore
import SwiftUI

/// ⌘K: one search over every repo, agent and Worker Echo knows, and the commands, so jumping
/// somewhere does not mean scanning tabs and the ledger.
struct QuickOpen: View {
    @EnvironmentObject private var model: AppModel
    /// Local state as an ObservableObject: the command-line tools lack the plugin `@State` needs.
    @StateObject private var search = QuickOpenSearch()
    @FocusState private var fieldFocused: Bool

    private static let shown = 12

    var body: some View {
        let results = matches
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            FoundryPopover(label: "Quick open") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Ledger.ink3)
                    TextField("Go to a repo, agent, Worker or command", text: $search.query)
                        .textFieldStyle(.plain)
                        .font(Ledger.font(16))
                        // Search terms, not prose: no completion panel over the results.
                        .autocorrectionDisabled()
                        .textContentType(.none)
                        .focused($fieldFocused)
                        .onSubmit { run(results) }
                        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rule() }

                if results.isEmpty {
                    FoundryPopoverBody {
                        Text("Nothing matches \u{201C}\(search.query)\u{201D}.")
                            .font(Ledger.font(13))
                            .foregroundStyle(Ledger.ink2)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            // A Foundry menu row (ui-ux/0125): the pointer moves the pick, as the arrows do.
                            FoundryPopoverItem(title: item.title, note: item.detail, picked: index == search.picked) {
                                search.picked = index
                                run(results)
                            }
                            .onHover { if $0 { search.picked = index } }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(width: 600)
            .padding(.top, 110)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onChange(of: search.query) { search.picked = 0 }
        // A big checkout has tens of thousands of files: they are matched off the main thread,
        // once typing pauses, and only the best few come back.
        .task(id: "\(search.query)|\(model.selectedCheckout ?? "")") {
            guard let root = model.selectedCheckout else { return search.files = [] }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let tree = model.checkoutFiles(root).tree
            let query = search.query
            let job = Task.detached(priority: .userInitiated) { quickOpenFiles(query, in: tree, limit: Self.shown) }
            let found = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard !Task.isCancelled else { return }
            search.files = found.map { (root, $0.score, $0.path) }
        }
        .onExitCommand(perform: close)
    }

    /// The best matches, best first; with no query, the commands and the current repo's agents.
    private var matches: [QuickOpenItem] {
        var scored = items.compactMap { item in
            quickOpenScore(search.query, item.title).map { ($0, item) }
                ?? quickOpenScore(search.query, item.detail).map { ($0 - 10, item) }
        }
        // The selected checkout's files, after everything else, so a command or agent of the
        // same name still comes first.
        for (root, score, path) in search.files where root == model.selectedCheckout {
            let dir = (path as NSString).deletingLastPathComponent
            scored.append((score, QuickOpenItem(id: "file \(path)", title: (path as NSString).lastPathComponent,
                                                detail: dir.isEmpty ? "File" : "File in \(dir)") {
                model.fileCursor[root] = path
                model.preview = FileRef(root: root, path: path)
            }))
        }
        // A stable sort keeps the listing order (commands, then repos, agents, Workers) among equals.
        return scored.enumerated()
            .sorted { ($0.element.0, -$0.offset) > ($1.element.0, -$1.offset) }
            .prefix(Self.shown)
            .map(\.element.1)
    }

    private var items: [QuickOpenItem] {
        var items: [QuickOpenItem] = [
            QuickOpenItem(id: "new-orchestrator", title: "New Orchestrator", detail: "Command") {
                model.showNewSession(repo: model.selectedRepo, kind: .orchestrator)
            },
            QuickOpenItem(id: "new-terminal", title: "New Terminal", detail: "Command, a shell in the repo") {
                model.openTerminal()
            },
            QuickOpenItem(id: "fan-out", title: "Fan Out a Task", detail: "Command, several Workers try it") {
                model.showFanOut()
            },
            QuickOpenItem(id: "ledger", title: model.ledgerCollapsed ? "Expand Ledger" : "Collapse Ledger", detail: "Command") {
                model.toggleLedger()
            },
            QuickOpenItem(id: "settings", title: "Settings", detail: "Command") {
                model.showSettings()
            },
        ]
        if let (_, worker) = model.selectedWorker {
            items.insert(QuickOpenItem(id: "changes", title: model.changesSelected ? "Hide Changes" : "Show Changes",
                                       detail: "Command, \(worker.id)'s diff") {
                model.toggleChanges()
            }, at: 2)
            if worker.fanout != nil, let (repo, _) = model.selectedWorker {
                items.insert(QuickOpenItem(id: "compare", title: "Compare Tries",
                                           detail: "Command, every try of \(worker.id)'s Task") {
                    model.show(.compare, repo: repo, worker: worker)
                }, at: 3)
            }
        }
        for session in model.sessions {
            let repo = session.repo
            items.append(QuickOpenItem(id: "repo \(repo)", title: session.name, detail: "Repo, \(session.shortPath)") {
                model.selectSession(repo)
            })
            for agent in model.agents(repo) {
                let kind = agent.kindName
                items.append(QuickOpenItem(id: "agent \(repo) \(agent.id)", title: agent.displayName, detail: "\(kind) in \(session.name)") {
                    model.select(.agent(repo: repo, id: agent.id))
                })
            }
            for worker in model.snapshot(repo).workers {
                items.append(QuickOpenItem(id: "worker \(repo) \(worker.id)", title: "\(worker.id) \(worker.title)", detail: "\(worker.profile), \(worker.phaseLabel) in \(session.name)") {
                    model.select(.worker(repo: repo, id: worker.id))
                })
            }
        }
        if model.filesShown {
            items.append(QuickOpenItem(id: "ignored", title: model.showIgnoredFiles ? "Hide Ignored Files" : "Show Ignored Files",
                                       detail: "Command, files .gitignore covers") {
                model.showIgnoredFiles.toggle()
            })
            items.append(QuickOpenItem(id: "search ignored", title: model.searchIgnoredFiles ? "Stop Searching Ignored Files" : "Search Ignored Files",
                                       detail: "Command, text search in files .gitignore covers") {
                model.searchIgnoredFiles.toggle()
            })
        }
        return items
    }

    private func move(_ step: Int, in results: [QuickOpenItem]) {
        guard !results.isEmpty else { return }
        search.picked = (search.picked + step + results.count) % results.count
    }

    private func run(_ results: [QuickOpenItem]) {
        guard results.indices.contains(search.picked) else { return }
        let item = results[search.picked]
        close()
        item.action()
    }

    private func close() {
        model.quickOpenShown = false
    }
}

final class QuickOpenSearch: ObservableObject {
    @Published var query = ""
    /// The highlighted result; Return runs it.
    @Published var picked = 0
    /// The best files for the query, in the checkout they were matched in.
    @Published var files: [(root: String, score: Int, path: String)] = []
}

struct QuickOpenItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let action: () -> Void
}

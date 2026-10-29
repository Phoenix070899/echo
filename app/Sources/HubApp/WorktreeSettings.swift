import HubCore
import SwiftUI

/// Settings' Worktrees: per repo, the ignored files a new worktree gets from the main checkout,
/// and the setup command run there before its agent starts. Kept in the repo's
/// `.echo/settings.json`, so a team can share it through git.
@MainActor
final class WorktreeSettingsModel: ObservableObject {
    @Published var repo: String?
    @Published var saved: RepoSettings?
    @Published var setup = ""
    /// One path per line.
    @Published var copy = ""
    @Published var failure: String?
    private let client = DaemonClient()

    var changed: Bool {
        guard let saved else { return false }
        return setup.trimmingCharacters(in: .whitespaces) != (saved.setup ?? "") || paths != saved.copy
    }

    private var paths: [String] {
        copy.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func load() {
        guard let repo else { return }
        run(nil, repo)
    }

    func save() {
        guard let repo else { return }
        run(["setup": setup.trimmingCharacters(in: .whitespaces), "copy": paths], repo)
    }

    func revert() {
        guard let saved else { return }
        show(saved)
    }

    private func show(_ settings: RepoSettings) {
        saved = settings
        setup = settings.setup ?? ""
        copy = settings.copy.joined(separator: "\n")
    }

    private func run(_ patch: [String: Any]?, _ repo: String) {
        let client = client
        nonisolated(unsafe) let patch = patch
        Task.detached {
            let result = Result { try client.repoSettings(repo, patch: patch) }
            await MainActor.run {
                switch result {
                case .success(let settings):
                    self.failure = nil
                    self.show(settings)
                case .failure(let error):
                    self.failure = "\(error)"
                }
            }
        }
    }
}

struct WorktreeSettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var worktrees = WorktreeSettingsModel()

    var body: some View {
        Section {
            Picker("Repo", selection: $worktrees.repo) {
                ForEach(model.sessions) { session in
                    Text(URL(fileURLWithPath: session.repo).lastPathComponent).tag(Optional(session.repo))
                }
            }
            TextField(text: $worktrees.setup, prompt: Text("pnpm install")) { Text("Setup").font(Ledger.font(13)) }
                .font(.system(size: 12, design: .monospaced))
            Text("Runs in each new worktree before its agent starts, in your login shell, where you can watch it. When it fails, the agent does not start.")
                .font(Ledger.font(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(text: $worktrees.copy, prompt: Text(".env"), axis: .vertical) { Text("Copy").font(Ledger.font(13)) }
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...6)
            Text("Files git ignores, one per line, copied from the main checkout into each new worktree that lacks them; a folder is copied whole.")
                .font(Ledger.font(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let path = worktrees.saved?.path {
                    Text(worktrees.changed ? "Not saved yet." : "Saved in \(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)/settings.json; commit it to share with your team.")
                        .font(Ledger.font(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert", action: worktrees.revert)
                    .disabled(!worktrees.changed)
                Button("Save", action: worktrees.save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!worktrees.changed)
            }
        }
        // On the section, which always shows: an empty view never appears, so it would never load.
        .onAppear {
            worktrees.repo = worktrees.repo ?? model.selectedRepo ?? model.sessions.first?.repo
            worktrees.load()
        }
        .onChange(of: worktrees.repo) { worktrees.load() }
        if let failure = worktrees.failure {
            Section {
                Text(failure)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

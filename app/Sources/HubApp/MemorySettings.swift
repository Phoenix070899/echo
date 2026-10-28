import AppKit
import HubCore
import SwiftUI

/// Settings' Preferences and Lessons: the human's standing instructions for every repo, and what
/// Workers learned about one repo. Both are files in the daemon's state; this reads them fresh.
@MainActor
final class MemoryModel: ObservableObject {
    @Published var files: MemoryFiles?
    @Published var repo: String?
    @Published var failure: String?
    @Published var newPreference = ""
    @Published var section = ""
    @Published var newLesson = ""
    private let client = DaemonClient()

    func refresh() {
        let (client, repo) = (client, repo)
        run({ try client.memory(repo: repo) }) { files in
            self.files = files
            if !files.preferences.sections.contains(self.section) { self.section = files.preferences.sections.first ?? "" }
        }
    }

    func add(_ file: String) {
        let text = (file == "preferences" ? newPreference : newLesson).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let (client, repo, section) = (client, repo, section)
        run({ try client.editMemory("add", file: file, text: text, section: section, repo: repo) }) {
            if file == "preferences" { self.newPreference = "" } else { self.newLesson = "" }
            self.refresh()
        }
    }

    func remove(_ file: String, _ bullet: MemoryFiles.Bullet) {
        let (client, repo) = (client, repo)
        run({ try client.editMemory("remove", file: file, text: bullet.text, repo: repo) }) { self.refresh() }
    }

    private func run<T>(_ work: @escaping @Sendable () throws -> T, then: @escaping @MainActor (T) -> Void) {
        Task.detached {
            let result = Result { try work() }
            await MainActor.run {
                switch result {
                case .success(let value):
                    self.failure = nil
                    then(value)
                case .failure(let error):
                    self.failure = "\(error)"
                }
            }
        }
    }
}

struct MemorySettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var memory = MemoryModel()

    var body: some View {
        Group {
            // Something is always shown: an empty Group never appears, so it would never load.
            if let files = memory.files {
                preferences(files.preferences)
                lessons(files.lessons)
            } else if memory.failure == nil {
                Section { Text("Reading…").foregroundStyle(.secondary) }
            }
            if let failure = memory.failure {
                Section {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear {
            memory.repo = memory.repo ?? model.selectedRepo ?? model.sessions.first?.repo
            memory.refresh()
        }
        .onChange(of: memory.repo) { memory.refresh() }
    }

    private func preferences(_ prefs: MemoryFiles.Preferences) -> some View {
        Section {
            if prefs.bullets.isEmpty {
                Text("None yet. Tell an Orchestrator how you like work done, or add a line here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(prefs.sections, id: \.self) { section in
                let lines = prefs.bullets.filter { $0.section == section }
                if !lines.isEmpty {
                    Text(section)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(lines, id: \.self) { bullet in
                        BulletRow(text: bullet.text) { memory.remove("preferences", bullet) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("New preference", text: $memory.newPreference, prompt: Text("Never push without a review"))
                    .onSubmit { memory.add("preferences") }
                if prefs.sections.count > 1 {
                    Picker("Under", selection: $memory.section) {
                        ForEach(prefs.sections, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Button("Add") { memory.add("preferences") }
                    .disabled(memory.newPreference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            footer("Every Worker and Orchestrator, in every repo, applies these.", path: prefs.path)
        } header: {
            Text("Preferences")
        }
    }

    @ViewBuilder
    private func lessons(_ lessons: MemoryFiles.Lessons?) -> some View {
        Section {
            Picker("Repo", selection: $memory.repo) {
                ForEach(model.sessions) { session in
                    Text(URL(fileURLWithPath: session.repo).lastPathComponent).tag(Optional(session.repo))
                }
            }
            if let lessons {
                if lessons.bullets.isEmpty {
                    Text("None yet. Workers add one with echoctl done --lesson when they find something the next Worker needs.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lessons.bullets, id: \.self) { bullet in
                    BulletRow(text: bullet.text) { memory.remove("lessons", bullet) }
                }
                HStack(spacing: 8) {
                    TextField("New lesson", text: $memory.newLesson, prompt: Text("Run make db before the tests"))
                        .onSubmit { memory.add("lessons") }
                    Button("Add") { memory.add("lessons") }
                        .disabled(memory.newLesson.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                footer("\(lessons.bullets.count) of \(lessons.limit) before an ino Worker merges them. Every new Worker and Orchestrator in this repo reads them.",
                       path: lessons.path)
            }
        } header: {
            Text("Lessons")
        }
    }

    private func footer(_ text: String, path: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open in Editor") { openFile(path) }
                .disabled(!FileManager.default.fileExists(atPath: path))
        }
    }

    private func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

/// One line of a file, with a delete button that shows on hover.
private struct BulletRow: View {
    let text: String
    let remove: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ledger.ink2)
            .opacity(hover.on ? 1 : 0)
            .help("Delete this line")
            .accessibilityLabel("Delete")
        }
        .onHover { hover.on = $0 }
    }
}

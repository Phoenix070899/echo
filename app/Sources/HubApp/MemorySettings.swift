import AppKit
import Foundry
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
        VStack(alignment: .leading, spacing: 40) {
            // Something is always shown: an empty view never appears, so it would never load.
            if let files = memory.files {
                preferences(files.preferences)
                lessons(files.lessons)
            } else if memory.failure == nil {
                Pending("Reading…")
                    .font(Ledger.font(15))
                    .foregroundStyle(Ledger.ink3)
            }
            if let failure = memory.failure {
                SettingsNote(failure, problem: true)
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            memory.repo = memory.repo ?? model.selectedRepo ?? model.sessions.first?.repo
            memory.refresh()
        }
        .onChange(of: memory.repo) { memory.refresh() }
    }

    private func preferences(_ prefs: MemoryFiles.Preferences) -> some View {
        SettingsGroup("Preferences") {
            if prefs.bullets.isEmpty {
                SettingsRow {
                    SettingsNote("None yet. Tell an Orchestrator how you like work done, or add a line here.", size: 15)
                }
            }
            ForEach(prefs.sections, id: \.self) { section in
                let lines = prefs.bullets.filter { $0.section == section }
                if !lines.isEmpty {
                    SettingsLabel(section)
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                    ForEach(lines, id: \.self) { bullet in
                        BulletRow(text: bullet.text) { memory.remove("preferences", bullet) }
                    }
                }
            }
            SettingsRow {
                HStack(spacing: 10) {
                    TextField("New preference", text: $memory.newPreference, prompt: Text("Never push without a review"))
                        .labelsHidden()
                        .squareField()
                        .onSubmit { memory.add("preferences") }
                    if prefs.sections.count > 1 {
                        SquarePicker(selection: $memory.section, options: prefs.sections.map { ($0, $0) }, label: "Under")
                            .frame(width: 160)
                    }
                    Button("Add") { memory.add("preferences") }
                        .buttonStyle(SettingsButtonStyle(height: 40))
                        .disabled(memory.newPreference.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                footer("Every Worker and Orchestrator, in every repo, applies these.", path: prefs.path)
            }
        }
    }

    @ViewBuilder
    private func lessons(_ lessons: MemoryFiles.Lessons?) -> some View {
        SettingsGroup("Lessons") {
            SettingsRow("Repo") {
                SquarePicker(selection: $memory.repo, options: model.sessions.map {
                    (Optional($0.repo), URL(fileURLWithPath: $0.repo).lastPathComponent)
                }, label: "Repo")
            }
            if let lessons {
                if lessons.bullets.isEmpty {
                    SettingsRow {
                        SettingsNote("None yet. Workers add one with echoctl done --lesson when they find something the next Worker needs.", size: 15)
                    }
                }
                ForEach(lessons.bullets, id: \.self) { bullet in
                    BulletRow(text: bullet.text) { memory.remove("lessons", bullet) }
                }
                SettingsRow {
                    HStack(spacing: 10) {
                        TextField("New lesson", text: $memory.newLesson, prompt: Text("Run make db before the tests"))
                            .labelsHidden()
                            .squareField()
                            .onSubmit { memory.add("lessons") }
                        Button("Add") { memory.add("lessons") }
                            .buttonStyle(SettingsButtonStyle(height: 40))
                            .disabled(memory.newLesson.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    footer("\(lessons.bullets.count) of \(lessons.limit) before an ino Worker merges them. Every new Worker and Orchestrator in this repo reads them.",
                           path: lessons.path)
                }
            }
        }
    }

    private func footer(_ text: String, path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            SettingsNote(text)
            Button("Open in Editor") { openFile(path) }
                .buttonStyle(.ledgerLink)
                .fixedSize()
                .disabled(!FileManager.default.fileExists(atPath: path))
        }
    }

    private func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

/// One line of a file over a 1 pt rule, with a delete button that shows on hover.
private struct BulletRow: View {
    let text: String
    let remove: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(Ledger.font(15))
                .foregroundStyle(Ledger.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ledger.ink2)
            .opacity(hover.on ? 1 : 0)
            .help("Delete this line")
            .accessibilityLabel("Delete")
        }
        .padding(.vertical, 12)
        .background(hover.on ? Ledger.wash : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
        .onHover { hover.on = $0 }
    }
}

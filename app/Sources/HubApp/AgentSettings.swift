import AppKit
import HubCore
import SwiftUI

/// Settings' Agents tab: what agents run with, each Profile, and the Orchestrator's rules. Everything lives in the daemon's files, so it reads them fresh each time.
@MainActor
final class AgentSettingsModel: ObservableObject {
    @Published var settings: AgentSettings?
    @Published var profiles: [WorkerProfile] = []
    @Published var picked = ""
    @Published var failure: String?
    /// The default model as typed, saved on Return or when the field is left.
    @Published var model = ""
    private let client = DaemonClient()
    var repo: String?

    var profile: WorkerProfile? { profiles.first { $0.name == picked } ?? profiles.first }

    func refresh() {
        let (client, repo) = (client, repo)
        run({ (try client.agentSettings(), try client.profiles(repo: repo)) }) { settings, profiles in
            self.settings = settings
            self.model = settings.model ?? ""
            self.profiles = profiles
            if !profiles.contains(where: { $0.name == self.picked }) { self.picked = profiles.first?.name ?? "" }
        }
    }

    func set(_ key: String, _ value: Any) {
        let client = client
        run({ try client.setAgentSettings([key: value]) }) { self.settings = $0; self.refresh() }
    }

    /// Sets one of the picked Profile's own fields; Echo's own Profile is copied into yours first.
    func setField(_ key: String, _ value: String) {
        guard let name = profile?.name else { return }
        let (client, repo) = (client, repo)
        let level = profile?.level == "repo" ? "repo" : "yours"
        run({ try client.profile("set", name: name, level: level, repo: repo, fields: [key: value]) }) { _ in self.refresh() }
    }

    /// Opens the Profile's file in the human's editor, copying Echo's own into yours first.
    func editFile() {
        guard let profile else { return }
        let (client, repo) = (client, repo)
        run({ () -> String in
            if profile.level == "built-in" {
                return try client.profile("copy", name: profile.name, repo: repo)
            }
            return profile.path ?? ""
        }) { path in
            if !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            self.refresh()
        }
    }

    func reset() {
        guard let profile, let level = profile.level, level != "built-in" else { return }
        let below = profile.replaces?.last.map { "the \($0) one" } ?? "nothing: it is the only one"
        let alert = NSAlert()
        alert.messageText = "Reset \(profile.name)?"
        alert.informativeText = profile.replaces?.isEmpty == false
            ? "Your changes to it are deleted, and \(below) is used again."
            : "It is deleted; no other \(profile.name) exists, so Workers can no longer start as it."
        alert.addButton(withTitle: profile.replaces?.isEmpty == false ? "Reset" : "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (client, repo) = (client, repo)
        run({ try client.profile("reset", name: profile.name, level: level, repo: repo) }) { _ in self.refresh() }
    }

    func newProfile() {
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "Lowercase letters, digits, and -, like code-reviewer. It opens in your editor to fill in."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "code-reviewer"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let (client, repo) = (client, repo)
        run({ try client.profile("new", name: name, repo: repo) }) { path in
            self.picked = name
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            self.refresh()
        }
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

/// The CLI and model every agent runs with unless its Profile or the repo says otherwise, then
/// each Profile.
struct AgentsSettings: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        Section {
            Picker("CLI", selection: Binding(get: { agents.settings?.cli ?? "claude" }, set: { agents.set("cli", $0) })) {
                ForEach(agentCLIs, id: \.self) { Text($0).tag($0) }
            }
            TextField("Model", text: $agents.model, prompt: Text("the CLI's own default"))
                .onSubmit { agents.set("model", agents.model.trimmingCharacters(in: .whitespaces)) }
            Text("Every agent's default. A repo's .echo/settings.json and a Profile's own CLI and model come first. Name models as provider/model, like openai/gpt-5.6-terra.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            Picker("Profile", selection: $agents.picked) {
                ForEach(agents.profiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            if let profile = agents.profile {
                LabeledContent("From", value: profile.origin)
                LabeledContent("Runs with", value: "\(profile.cli ?? "claude") \(profile.model)")
                if let problem = profile.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Its CLI", selection: Binding(get: { profile.ownCli ?? "" }, set: { agents.setField("cli", $0) })) {
                    Text("The default").tag("")
                    ForEach(agentCLIs, id: \.self) { Text($0).tag($0) }
                }
                ProfileModelField(agents: agents, profile: profile)
                Picker("Effort", selection: Binding(get: { profile.effort ?? "" }, set: { agents.setField("effort", $0) })) {
                    Text("The CLI's own").tag("")
                    ForEach(["low", "medium", "high", "xhigh"], id: \.self) { Text($0).tag($0) }
                }
                Text(profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("New Profile…", action: agents.newProfile)
                    Spacer()
                    if profile.level != "built-in" {
                        Button(profile.replaces?.isEmpty == false ? "Reset" : "Delete…", action: agents.reset)
                    }
                    Button("Edit Role…", action: agents.editFile)
                        .help("Opens its file in your editor; Echo's own is copied into yours first")
                }
            }
            Text("A change to Echo's own Profile is saved as yours, in ~/.echo/profiles; Reset goes back to Echo's. A change applies to Workers started after it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let failure = agents.failure {
            Section {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// The picked Profile's own model, saved on Return.
private struct ProfileModelField: View {
    @ObservedObject var agents: AgentSettingsModel
    let profile: WorkerProfile
    @StateObject private var draft = Draft()

    var body: some View {
        TextField("Its model", text: $draft.text, prompt: Text("the default"))
            .onSubmit { agents.setField("model", draft.text.trimmingCharacters(in: .whitespaces)) }
            .onAppear { draft.text = profile.ownModel ?? "" }
            .onChange(of: profile) { draft.text = profile.ownModel ?? "" }
    }
}

/// How every Orchestrator works, where it differs from orchestrator.md.
struct OrchestratorSettings: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        if let rules = agents.settings?.orchestrator {
            Section("Orchestrators") {
                Stepper("At most \(rules.maxWorkers) Workers at once", value: Binding(
                    get: { rules.maxWorkers }, set: { agents.set("maxWorkers", $0) }), in: 1...16)
                Toggle("Wait for my go before Tasks that write code", isOn: Binding(
                    get: { rules.planApproval }, set: { agents.set("planApproval", $0) }))
                Toggle("Have sasuke review each writing Worker", isOn: Binding(
                    get: { rules.review }, set: { agents.set("review", $0) }))
                Toggle("Merge verified branches without asking", isOn: Binding(
                    get: { rules.mergeWithoutAsking }, set: { agents.set("mergeWithoutAsking", $0) }))
                Text("Applies to Orchestrators started or resumed after a change. Anything else you want them to do goes in your Preferences: tell an Orchestrator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

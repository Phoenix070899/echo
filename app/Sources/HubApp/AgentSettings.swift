import HubCore
import SwiftUI

/// What the Teams section's Defaults entry edits: what agents run with, and the Orchestrator's rules. Everything lives in the daemon's files, so it reads them fresh each time.
@MainActor
final class AgentSettingsModel: ObservableObject {
    @Published var settings: AgentSettings?
    @Published var failure: String?
    /// The default model as typed, saved on Return or when the field is left.
    @Published var model = ""
    private let client = DaemonClient()
    var repo: String?

    func refresh() {
        let client = client
        run({ try client.agentSettings() }) { settings in
            self.settings = settings
            self.model = settings.model ?? ""
        }
    }

    func set(_ key: String, _ value: Any) {
        let client = client
        run({ try client.setAgentSettings([key: value]) }) { self.settings = $0; self.refresh() }
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

/// The CLI and model every agent runs with unless its Profile or the repo says otherwise.
struct DefaultsSettings: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        Section("Every agent") {
            Picker("CLI", selection: Binding(get: { agents.settings?.cli ?? "claude" }, set: { agents.set("cli", $0) })) {
                ForEach(agentCLIs, id: \.self) { Text($0).tag($0) }
            }
            TextField("Model", text: $agents.model, prompt: Text("the CLI's own default"))
                .onSubmit { agents.set("model", agents.model.trimmingCharacters(in: .whitespaces)) }
            Toggle("Use for every agent", isOn: Binding(
                get: { agents.settings?.forceCli ?? false }, set: { agents.set("forceCli", $0) }))
            Text("Every agent's default. A repo's .echo/settings.json comes first. When off, a Profile's own CLI and model come first; when on, every agent runs this CLI and model. Name models as provider/model, like openai/gpt-5.6-terra; Kiro takes its own ids, like claude-sonnet-5.5.")
                .font(Ledger.font(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The daemon's message when a change here was refused.
struct AgentFailure: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        if let failure = agents.failure {
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
                    .font(Ledger.font(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

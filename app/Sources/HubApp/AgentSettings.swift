import Foundry
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

/// The Teams section's Defaults entry (ui-ux/0101): a page like every other section's, beside the
/// list, with what every agent starts with and the Orchestrators' default rules.
struct DefaultsPane: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                SettingsHead(label: "\(SettingsLook.number(.teams)) / \(SettingsSection.teams.title)", title: "Defaults", size: 40)
                DefaultsSettings(agents: agents)
                OrchestratorSettings(agents: agents)
                if let failure = agents.failure {
                    SettingsNote(failure, problem: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: SettingsLook.column)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// The CLI and model every agent runs with unless its Profile or the repo says otherwise.
struct DefaultsSettings: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        SettingsGroup("Every agent") {
            SettingsRow("CLI") {
                SquarePicker(selection: Binding(get: { agents.settings?.cli ?? "claude" }, set: { agents.set("cli", $0) }),
                             options: agentCLIs.map { ($0, $0) }, label: "CLI")
            }
            SettingsRow("Model") {
                TextField("Model", text: $agents.model, prompt: Text("the CLI's own default"))
                    .labelsHidden()
                    .squareField()
                    .onSubmit { agents.set("model", agents.model.trimmingCharacters(in: .whitespaces)) }
            }
            SettingsRow("Every agent") {
                Checkbox("Use for every agent", isOn: Binding(
                    get: { agents.settings?.forceCli ?? false }, set: { agents.set("forceCli", $0) }))
                SettingsNote("Every agent's default. A repo's .echo/settings.json comes first. When off, a Profile's own CLI and model come first; when on, every agent runs this CLI and model. Name models as provider/model, like openai/gpt-5.6-terra; Kiro takes its own ids, like claude-sonnet-5.5.")
            }
        }
    }
}

/// How every Orchestrator works, where it differs from orchestrator.md.
struct OrchestratorSettings: View {
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        if let rules = agents.settings?.orchestrator {
            SettingsGroup("Orchestrators") {
                SettingsRow("Workers at once") {
                    SquareStepper(text: "At most \(rules.maxWorkers)",
                                  minus: rules.maxWorkers > 1 ? { agents.set("maxWorkers", rules.maxWorkers - 1) } : nil,
                                  plus: rules.maxWorkers < 16 ? { agents.set("maxWorkers", rules.maxWorkers + 1) } : nil,
                                  label: "Workers at once")
                }
                SettingsRow("Rules") {
                    Group {
                        Checkbox("Wait for my go before Tasks that write code", isOn: Binding(
                            get: { rules.planApproval }, set: { agents.set("planApproval", $0) }))
                        Checkbox("Have sasuke review each writing Worker", isOn: Binding(
                            get: { rules.review }, set: { agents.set("review", $0) }))
                        Checkbox("Merge verified branches without asking", isOn: Binding(
                            get: { rules.mergeWithoutAsking }, set: { agents.set("mergeWithoutAsking", $0) }))
                    }
                    SettingsNote("Applies to Orchestrators started or resumed after a change. Anything else you want them to do goes in your Preferences: tell an Orchestrator.")
                }
            }
        }
    }
}

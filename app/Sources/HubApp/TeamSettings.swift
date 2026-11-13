import AppKit
import HubCore
import SwiftUI

/// Settings' Teams page: the Teams to pick from, and the editor for the one picked. The Teams live
/// in the daemon's files, so the page reads them fresh each time it opens.
@MainActor
final class TeamSettingsModel: ObservableObject {
    @Published var teams: [Team] = []
    @Published var profileNames: [String] = []
    /// The human's Orchestrator settings: what a rule the Team leaves out falls back to.
    @Published var fallbackRules: AgentSettings.OrchestratorRules?
    @Published var fallbackCli = "claude"
    /// The Team being edited; nil while the form holds one that has no file yet.
    @Published var picked: String?
    @Published var form = TeamForm()
    /// The daemon's message about the last load, save or delete.
    @Published var failure: String?
    private var saved = TeamForm()
    private let client = DaemonClient()
    var repo: String?

    var team: Team? { teams.first { $0.name == picked } }

    /// Echo's own Teams are not written; duplicate one to change it.
    var readOnly: Bool { !form.isNew && team?.origin == "shipped" }

    var changed: Bool { form != saved }

    var canSave: Bool { !readOnly && changed && !saving }

    /// Only the human's and the repo's own Teams can be deleted.
    var canDelete: Bool { !form.isNew && team.map { $0.origin == "user" || $0.origin == "repo" } == true }

    @Published private(set) var saving = false

    func refresh(select name: String? = nil) {
        let (client, repo) = (client, repo)
        run({ (try client.teams(repo: repo), try client.profiles(repo: repo), try client.agentSettings()) }) { teams, profiles, settings in
            self.teams = teams
            self.profileNames = profiles.map(\.name)
            self.fallbackRules = settings.orchestrator
            self.fallbackCli = settings.cli ?? "claude"
            if let name, teams.contains(where: { $0.name == name }) {
                self.pick(name)
            } else if !self.form.isNew, !teams.contains(where: { $0.name == self.picked }) {
                self.pick(teams.first?.name)
            }
        }
    }

    func pick(_ name: String?) {
        picked = name
        failure = nil
        form = name.flatMap { name in teams.first { $0.name == name } }.map(TeamForm.init(team:)) ?? TeamForm()
        saved = form
    }

    func newTeam() {
        picked = nil
        failure = nil
        form = TeamForm()
        saved = form
    }

    func duplicate() {
        guard let team else { return }
        picked = nil
        failure = nil
        form = TeamForm(copying: team, taking: teams.map(\.name))
        saved = TeamForm()
    }

    func save() {
        if let blocker = form.blocker {
            failure = blocker
            return
        }
        let (client, params) = (client, form.saveParams(repo: repo))
        saving = true
        run({ try client.saveTeam(params) }, then: { name in
            self.saving = false
            self.refresh(select: name)
        }, otherwise: { self.saving = false })
    }

    func revert() {
        failure = nil
        form = saved
    }

    func delete() {
        guard let team, canDelete else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(team.name)?"
        alert.informativeText = team.replaces.isEmpty
            ? "Its file is deleted. Orchestrators already running with it keep running, and a resume finds no \(team.name)."
            : "Its file is deleted, and the \(team.replaces.last ?? "") one is used again."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (client, repo) = (client, repo)
        run({ try client.deleteTeam(name: team.name, level: team.origin, repo: repo) }) { _ in
            self.pick(nil)
            self.refresh()
        }
    }

    /// The CLI a model field is checked against: the one picked above it, else the settings'.
    func effectiveCli(_ picked: String) -> String { picked.isEmpty ? fallbackCli : picked }

    /// The Profiles an override row can name: all of them, and the row's own if no Profile has it.
    func profileOptions(including current: String) -> [String] {
        profileNames.contains(current) ? profileNames : profileNames + [current]
    }

    private func run<T>(_ work: @escaping @Sendable () throws -> T, then: @escaping @MainActor (T) -> Void,
                        otherwise: @escaping @MainActor () -> Void = {}) {
        Task.detached {
            let result = Result { try work() }
            await MainActor.run {
                switch result {
                case .success(let value):
                    self.failure = nil
                    then(value)
                case .failure(let error):
                    self.failure = "\(error)"
                    otherwise()
                }
            }
        }
    }
}

/// The list of Teams, then the picked one's fields.
struct TeamsSettings: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section {
            if teams.form.isNew {
                TeamRow(name: teams.form.name.isEmpty ? "New Team" : teams.form.name, label: "not saved yet",
                        problem: nil, picked: true) {}
            }
            ForEach(teams.teams) { team in
                TeamRow(name: team.name, label: team.origin, problem: team.problem,
                        picked: !teams.form.isNew && team.name == teams.picked) { teams.pick(team.name) }
            }
            HStack {
                Button("New Team", action: teams.newTeam)
                Button("Duplicate", action: teams.duplicate)
                    .disabled(teams.form.isNew || teams.team == nil)
                Spacer()
                if teams.canDelete {
                    Button("Delete…", action: teams.delete)
                }
            }
            Text("A Team sets what an Orchestrator and its Workers run with. It applies when an Orchestrator starts or resumes. Echo's own Teams cannot be changed: duplicate one to make it yours.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        TeamAbout(teams: teams)
        Group {
            TeamOrchestrator(teams: teams)
            TeamWorkers(teams: teams)
            TeamRules(teams: teams)
            TeamInstructions(teams: teams)
        }
        .disabled(teams.readOnly)
        TeamSave(teams: teams)
    }
}

/// A Team in the list: flat, 30 pt at least, the picked one on the selected fill, and its problem
/// under it where it has one.
private struct TeamRow: View {
    let name: String
    let label: String
    let problem: String?
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .fontWeight(picked ? .medium : .regular)
                        .foregroundStyle(Ledger.ink)
                    Text(label)
                        .font(Ledger.font(11))
                        .foregroundStyle(Ledger.ink3)
                    Spacer(minLength: 0)
                }
                if let problem {
                    Text(problem)
                        .font(Ledger.font(11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? Ledger.selected : .clear, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The Team's name, where it comes from, and its description.
private struct TeamAbout: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section {
            if teams.form.isNew {
                TextField("Name", text: $teams.form.name, prompt: Text("lowercase letters, digits and -"))
                if teams.repo != nil {
                    Picker("Keep in", selection: $teams.form.level) {
                        Text("Yours, in ~/.echo/teams").tag(TeamForm.userLevel)
                        Text("This repo, in .echo/teams").tag(TeamForm.repoLevel)
                    }
                }
            } else if let team = teams.team {
                LabeledContent("From", value: origin(team))
            }
            if let problem = teams.team?.problem, !teams.form.isNew {
                Text(problem)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Description", text: $teams.form.description, prompt: Text("what this Team is for"), axis: .vertical)
                .lineLimit(1...3)
                .disabled(teams.readOnly)
        }
    }

    /// "user, replaces shipped"
    private func origin(_ team: Team) -> String {
        team.replaces.isEmpty ? team.origin : "\(team.origin), replaces \(team.replaces.joined(separator: ", "))"
    }
}

/// The CLI, model and effort the Orchestrator starts with, and when it is renewed.
private struct TeamOrchestrator: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section("Orchestrator") {
            CliPicker(title: "CLI", selection: $teams.form.orchestratorCli)
            TextField("Model", text: $teams.form.orchestratorModel,
                      prompt: Text(TeamForm.modelHint(cli: teams.effectiveCli(teams.form.orchestratorCli))))
            EffortPicker(title: "Effort", selection: $teams.form.orchestratorEffort)
            TextField("Renew at", text: $teams.form.rotateAt, prompt: Text("tokens of context, like 150000"))
            Text(teams.effectiveCli(teams.form.orchestratorCli) == "kiro"
                 ? "Kiro does not support renewal yet, so this is not used with it."
                 : "A running Orchestrator is renewed with a fresh context once it holds this many tokens. Empty leaves it to your settings.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What every Worker runs with, then the Profiles that differ.
private struct TeamWorkers: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section("Workers") {
            CliPicker(title: "CLI", selection: $teams.form.workersCli)
            TextField("Model", text: $teams.form.workersModel,
                      prompt: Text(TeamForm.modelHint(cli: teams.effectiveCli(teams.form.workersCli))))
            EffortPicker(title: "Effort", selection: $teams.form.workersEffort)
            Text("Set for every Worker, over what its Profile says. Empty leaves it to the Profile.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section("Profiles set apart") {
            ForEach($teams.form.overrides) { $row in
                HStack(spacing: 8) {
                    Picker("Profile", selection: $row.profile) {
                        ForEach(teams.profileOptions(including: row.profile), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    CliPicker(title: "CLI", selection: $row.cli).labelsHidden().fixedSize()
                    TextField("Model", text: $row.model,
                              prompt: Text(TeamForm.modelHint(cli: teams.effectiveCli(row.cli.isEmpty ? teams.form.workersCli : row.cli))))
                        .labelsHidden()
                    EffortPicker(title: "Effort", selection: $row.effort).labelsHidden().fixedSize()
                    Button("Remove") { teams.form.removeOverride(row.id) }
                        .buttonStyle(.ledgerLink)
                        .help("Take this Profile out of the Team's own settings")
                }
            }
            HStack {
                Button("Add a Profile") { teams.form.addOverride(from: teams.profileNames) }
                    .disabled(teams.form.overrides.count >= teams.profileNames.count)
                Spacer()
            }
            Text("Each row sets one Profile's CLI, model and effort, over the Team's Workers above.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How this Team's Orchestrator works. A rule not set here follows the human's Orchestrator settings.
private struct TeamRules: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section("Rules") {
            Stepper("At most \(maxWorkers) Workers at once", value: Binding(
                get: { maxWorkers }, set: { teams.form.maxWorkers = $0 }), in: 1...16)
            Toggle("Wait for my go before Tasks that write code", isOn: rule(\.planApproval, \.planApproval))
            Toggle("Have sasuke review each writing Worker", isOn: rule(\.review, \.review))
            Toggle("Merge verified branches without asking", isOn: rule(\.mergeWithoutAsking, \.mergeWithoutAsking))
            HStack {
                Text(isSet ? "These rules are the Team's own." : "Not set here: your Orchestrator settings apply.")
                    .font(Ledger.font(11))
                    .foregroundStyle(Ledger.ink3)
                Spacer()
                if isSet {
                    Button("Use my settings", action: clear)
                        .buttonStyle(.ledgerLink)
                        .disabled(teams.readOnly)
                }
            }
        }
    }

    private var maxWorkers: Int { teams.form.maxWorkers ?? teams.fallbackRules?.maxWorkers ?? 3 }

    private var isSet: Bool {
        let form = teams.form
        return form.maxWorkers != nil || form.planApproval != nil || form.review != nil || form.mergeWithoutAsking != nil
    }

    /// A toggle that shows the Team's value, else the human's, and sets the Team's.
    private func rule(_ own: WritableKeyPath<TeamForm, Bool?>, _ fallback: KeyPath<AgentSettings.OrchestratorRules, Bool>) -> Binding<Bool> {
        Binding(
            get: { teams.form[keyPath: own] ?? teams.fallbackRules?[keyPath: fallback] ?? false },
            set: { teams.form[keyPath: own] = $0 })
    }

    private func clear() {
        teams.form.maxWorkers = nil
        teams.form.planApproval = nil
        teams.form.review = nil
        teams.form.mergeWithoutAsking = nil
    }
}

/// Text added to the end of the Orchestrator's prompt.
private struct TeamInstructions: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section("Instructions") {
            TextField("Instructions", text: $teams.form.instructions,
                      prompt: Text("Anything this Team's Orchestrator should do or avoid"), axis: .vertical)
                .labelsHidden()
                .lineLimit(4...14)
            Text("Added to the end of the Orchestrator's prompt, after its rules.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
        }
    }
}

/// Save and Revert, and the daemon's message when it refused the Team.
private struct TeamSave: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section {
            if let failure = teams.failure {
                Text(failure)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if teams.readOnly {
                HStack {
                    Text("Echo's own Team. Duplicate it to change it.")
                        .font(Ledger.font(11))
                        .foregroundStyle(Ledger.ink3)
                    Spacer()
                    Button("Duplicate", action: teams.duplicate)
                }
            } else {
                HStack {
                    Text(teams.changed ? "Not saved yet." : "Saved.")
                        .font(Ledger.font(11))
                        .foregroundStyle(Ledger.ink3)
                    Spacer()
                    Button("Revert", action: teams.revert)
                        .disabled(!teams.changed)
                    Button("Save", action: teams.save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!teams.canSave)
                }
            }
        }
    }
}

/// A CLI, or the settings' own when none is picked.
private struct CliPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("The default").tag("")
            ForEach(agentCLIs, id: \.self) { Text($0).tag($0) }
        }
    }
}

private struct EffortPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("The CLI's own").tag("")
            ForEach(TeamForm.efforts, id: \.self) { Text($0).tag($0) }
        }
    }
}

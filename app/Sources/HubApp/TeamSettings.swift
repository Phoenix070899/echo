import AppKit
import HubCore
import SwiftUI

/// What the Teams section's right side shows.
enum TeamsPane: Equatable {
    case defaults, team
}

/// Settings' Teams section: the Teams to pick from, and the editor for the one picked. The Teams
/// live in the daemon's files, so the section reads them fresh each time it opens. The model is
/// the app's own, not a view's, so edits not yet saved survive until the human is asked about
/// them (ui-ux/0103).
@MainActor
final class TeamSettingsModel: ObservableObject {
    /// What is picked in the list: Defaults, or a Team (`picked`, or the new one).
    @Published var pane = TeamsPane.team
    @Published var teams: [Team] = []
    @Published var profileNames: [String] = []
    /// The Profiles with what each holds, which a Member's fields fall back to.
    @Published var profiles: [WorkerProfile] = []
    /// Your default CLI and model, the bottom of what a Member runs with.
    @Published var defaults = MemberDefaults()
    /// The Member whose inspector shows, by id; nil when none is picked.
    @Published var selectedMember: String?
    /// Why the last Member edit was refused, until the next edit or pick.
    @Published var memberNotice: String?
    /// Why the last command on the tree was refused: the one line under the tree (ui-ux/0102).
    @Published var treeNotice: String?
    /// The tree has the keyboard, so the page leaves Up and Down to it, and Save gives up Return.
    @Published var treeFocused = false
    /// Each change asks the view that owns that focus to take it: the tree, the Member's name
    /// field, and the settings page's own keys.
    @Published var treeFocusRequest = 0
    @Published var nameFocusRequest = 0
    @Published var pageFocusRequest = 0
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

    /// The picked Member, in the draft; nil when none is picked or an edit took it away.
    var member: Team.Member? { selectedMember.flatMap(form.member) }

    /// The Profile of that name; nil when none exists here.
    func profile(named name: String) -> WorkerProfile? { profiles.first { $0.name == name } }

    /// Echo's own Teams are not written; duplicate one to change it.
    var readOnly: Bool { !form.isNew && team?.origin == "shipped" }

    var changed: Bool { form != saved }

    var canSave: Bool { !readOnly && changed && !saving }

    /// Only the human's and the repo's own Teams can be deleted.
    var canDelete: Bool { !form.isNew && team.map { $0.origin == "user" || $0.origin == "repo" } == true }

    @Published private(set) var saving = false

    /// The card that asks what to do with unsaved edits is up.
    @Published private(set) var asking = false
    /// Where the human was going when the card came up.
    private var pending: (@MainActor () -> Void)?
    /// The first read of the Teams picks the first one, once.
    private var started = false

    func refresh(select name: String? = nil, then done: (@MainActor () -> Void)? = nil) {
        let (client, repo) = (client, repo)
        run({ (try client.teams(repo: repo), try client.profiles(repo: repo), try client.agentSettings()) }) { teams, profiles, settings in
            self.teams = teams
            self.profileNames = profiles.map(\.name)
            self.profiles = profiles
            self.fallbackRules = settings.orchestrator
            self.fallbackCli = settings.cli ?? "claude"
            self.defaults = MemberDefaults(settings: settings)
            if let name, teams.contains(where: { $0.name == name }) {
                self.pick(name)
            } else if !self.started, !self.changed {
                self.pick(teams.first?.name)
            } else if !self.form.isNew {
                if !teams.contains(where: { $0.name == self.picked }) {
                    self.pick(teams.first?.name)
                } else if !self.changed {
                    // Read fresh, unless the human has edits here.
                    self.pick(self.picked)
                }
            }
            self.started = true
            done?()
        }
    }

    /// Shows what the list entry names; unsaved edits are asked about first.
    func show(_ pane: TeamsPane) {
        leave { self.pane = pane }
    }

    /// Picks a Team in the list; unsaved edits are asked about first.
    func choose(_ name: String) {
        leave {
            self.pane = .team
            self.pick(name)
        }
    }

    /// Runs `go` now, or after the human has answered the card when edits are not saved: Save
    /// goes on once the Team is written, Discard goes on at once, Cancel never goes (ui-ux/0103).
    func leave(then go: @escaping @MainActor () -> Void) {
        if asking { return }
        guard UnsavedChanges.needsAsk(changed: changed, asking: asking) else {
            go()
            return
        }
        pending = go
        asking = true
    }

    func answer(_ answer: UnsavedAnswer) {
        guard asking else { return }
        let go = pending
        pending = nil
        asking = false
        switch UnsavedChanges.step(for: answer) {
        case .save:
            save { saved in
                if UnsavedChanges.afterSave(succeeded: saved) == .goOn { go?() }
            }
        case .discardAndGo:
            // A Team that was never saved has nothing to go back to: the first one is shown.
            if form.isNew { pick(teams.first?.name) } else { revert() }
            go?()
        case .stay, .goOn:
            break
        }
    }

    /// Shows the Team's fields; `pick` does not move the pane.
    func pick(_ name: String?) {
        picked = name
        failure = nil
        selectedMember = nil
        memberNotice = nil
        treeNotice = nil
        form = name.flatMap { name in teams.first { $0.name == name } }.map(TeamForm.init(team:)) ?? TeamForm()
        saved = form
    }

    func newTeam() {
        leave {
            self.pane = .team
            self.picked = nil
            self.failure = nil
            self.selectedMember = nil
            self.memberNotice = nil
            self.treeNotice = nil
            self.form = TeamForm()
            self.saved = self.form
        }
    }

    func duplicate() {
        guard let team else { return }
        leave {
            self.pane = .team
            self.picked = nil
            self.failure = nil
            self.selectedMember = nil
            self.memberNotice = nil
            self.treeNotice = nil
            self.form = TeamForm(copying: team, taking: self.teams.map(\.name))
            self.saved = TeamForm()
        }
    }

    /// Writes the Team; `done` hears whether it was written, after the list has been read again.
    func save(done: (@MainActor (Bool) -> Void)? = nil) {
        if let blocker = form.blocker {
            failure = blocker
            done?(false)
            return
        }
        guard !saving else {
            done?(false)
            return
        }
        let (client, params) = (client, form.saveParams(repo: repo))
        saving = true
        let keep = selectedMember
        run({ try client.saveTeam(params) }, then: { name in
            self.saving = false
            self.refresh(select: name) {
                // The Team is read again from its file, which drops the pick; the tree keeps it.
                if let keep, self.form.member(keep) != nil { self.selectedMember = keep }
                done?(true)
            }
        }, otherwise: {
            self.saving = false
            done?(false)
        })
    }

    func revert() {
        failure = nil
        memberNotice = nil
        treeNotice = nil
        form = saved
        // A Member the draft had added is gone; the Orchestrator is shown when the picked one is.
        if let id = selectedMember, form.member(id) == nil { selectedMember = nil }
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

    // MARK: Members

    /// Shows the Member's inspector.
    func selectMember(_ id: String?) {
        selectedMember = id
        memberNotice = nil
        treeNotice = nil
    }

    /// Renames the picked Member in the draft and keeps it picked; a refusal shows as the notice.
    func renameMember(_ id: String, to name: String) {
        memberNotice = form.renameMember(id, to: name)
        if memberNotice == nil, selectedMember == id {
            selectedMember = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Changes the Member's Action in the draft; a refusal shows as the notice.
    func changeAction(_ id: String, to action: String) {
        memberNotice = form.changeMemberAction(id, to: action)
    }

    /// Opens the Profile's file in the human's editor, copying Echo's own into yours first. The
    /// file is shared by every Team, so this is not a Member edit and not held in the draft.
    func editRole(of name: String) {
        guard let profile = profile(named: name) else { return }
        let (client, repo) = (client, repo)
        run({ () -> String in
            if profile.level == "built-in" {
                return try client.profile("copy", name: profile.name, repo: repo)
            }
            return profile.path ?? ""
        }) { path in
            if !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            self.refreshProfiles()
        }
    }

    /// Asks for a name, creates a Profile of that name and opens its file to fill in, then adds a
    /// `custom` Member on it to the draft, under `parent` or at level 1, and picks it. The Profile's
    /// file is written at once; the Member is held in the draft until Save.
    func newCustomWorker(under parent: String? = nil) {
        let alert = NSAlert()
        alert.messageText = "New custom Worker"
        alert.informativeText = "Name its Profile with lowercase letters, digits, and -, like code-reviewer. "
            + "The file opens in your editor to fill in, and the Worker is added to this Team."
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
            if !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            if let id = self.form.addCustomMember(profile: name, under: parent) {
                self.selectMember(id)
            } else {
                self.treeNotice = "The Profile \(name) is made, but no Member could be added for it: a Team holds at most "
                    + "\(TeamForm.maxMembers) Members and the tree goes \(TeamForm.maxDepth) deep."
            }
            self.refreshProfiles()
        }
    }

    /// Reads the Profiles again, leaving the Team's draft alone.
    private func refreshProfiles() {
        let (client, repo) = (client, repo)
        run({ try client.profiles(repo: repo) }) { profiles in
            self.profiles = profiles
            self.profileNames = profiles.map(\.name)
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

/// The inspector of what is picked in the tree (ui-ux/0101): the Orchestrator's fields, the Team's
/// name and rules among them, or the picked Member's; then Save and Revert.
struct TeamEditor: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        if let member = teams.member {
            // One inspector per Member, so a field half typed for one never lands on the next.
            MemberInspector(teams: teams, member: member)
                .id(member.id)
        } else {
            TeamAbout(teams: teams)
            Group {
                TeamOrchestrator(teams: teams)
                TeamWorkers(teams: teams)
                TeamRules(teams: teams)
                TeamInstructions(teams: teams)
            }
            .disabled(teams.readOnly)
        }
        TeamSave(teams: teams)
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
                    // Return renames in the tree, so Save gives up the key while the tree has it.
                    Button("Save") { teams.save() }
                        .keyboardShortcut(teams.treeFocused ? nil : .defaultAction)
                        .disabled(!teams.canSave)
                }
            }
        }
    }
}

/// A CLI, or the settings' own when none is picked.
struct CliPicker: View {
    let title: String
    @Binding var selection: String
    /// What the empty choice is called; a Member says "Not set" and its line says what follows.
    var unset = "The default"

    var body: some View {
        Picker(title, selection: $selection) {
            Text(unset).tag("")
            ForEach(agentCLIs, id: \.self) { Text($0).tag($0) }
        }
    }
}

struct EffortPicker: View {
    let title: String
    @Binding var selection: String
    var unset = "The CLI's own"

    var body: some View {
        Picker(title, selection: $selection) {
            Text(unset).tag("")
            ForEach(TeamForm.efforts, id: \.self) { Text($0).tag($0) }
        }
    }
}

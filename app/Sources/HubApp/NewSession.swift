import AppKit
import HubCore
import SwiftUI

/// Start a session: a modal in the middle of the window over a dimmed backdrop. Pick how to
/// work (an Orchestrator, or Claude Code on its own), the repo, an optional name, an optional
/// GitHub issue to start on, and the model.
struct NewSessionModal: View {
    @EnvironmentObject private var model: AppModel
    /// Local state as an ObservableObject: the command-line tools lack the plugin `@State` needs.
    @StateObject private var form = NewSessionForm()
    @FocusState private var nameFocused: Bool

    private var repos: [String] {
        var seen = Set<String>()
        return (form.chosen + model.sessions.map(\.repo)).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ZStack {
            ModalBackdrop(close: close)
            VStack(alignment: .leading, spacing: 0) {
                ModalHead(label: "New session", title: "Start a session",
                          detail: "Pick how you want to work, then a git repo.", close: close)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        StepLabel(number: 1, title: "Mode")
                        HStack(spacing: 12) {
                            ModeCard(kind: .orchestrator, picked: form.kind == .orchestrator,
                                     title: "Orchestrator",
                                     detail: "You talk to an Orchestrator. It hands Tasks to Workers and reports back.") {
                                form.kind = .orchestrator
                            }
                            ModeCard(kind: .claude, picked: form.kind == .claude,
                                     title: "Normal",
                                     detail: "One Claude Code terminal in the repo. Just you and the agent.") {
                                form.kind = .claude
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            StepLabel(number: 2, title: "Repo")
                            Spacer(minLength: 8)
                            Button("Choose another folder…", action: choose)
                                .buttonStyle(.ledgerLink)
                        }
                        if repos.isEmpty {
                            Text("No repos yet. Choose the folder of a git repo to start.")
                                .font(Ledger.font(13))
                                .foregroundStyle(Ledger.ink3)
                        } else {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(repos, id: \.self) { repo in
                                        RepoChoice(repo: repo, status: status(repo), picked: form.picked == repo) {
                                            form.picked = repo
                                        }
                                    }
                                }
                                .overlay(alignment: .top) { Rule() }
                            }
                            .frame(height: min(CGFloat(repos.count) * 41 + 1, 206))
                        }
                    }

                    if form.picked != nil {
                        CreateFromSection(form: form, submit: start)
                    }

                    // Name and Team share a row, keeping the dialog short enough for small windows.
                    // An Orchestrator takes its model from its Team, so the Team has the model's place.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                StepLabel(number: 4, title: "Name")
                                TextField(namePlaceholder, text: $form.name)
                                    .textFieldStyle(.plain)
                                    .font(Ledger.font(14))
                                    .padding(.horizontal, 10)
                                    .frame(height: 38)
                                    .background(Ledger.field)
                                    .overlay(Rectangle().strokeBorder(nameFocused ? Ledger.ink : Ledger.ink3, lineWidth: Ledger.hairline))
                                    .focused($nameFocused)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                if form.kind == .orchestrator {
                                    MonoLabel("Team")
                                    TeamPicker(form: form)
                                } else {
                                    MonoLabel("Model")
                                    FieldMenu(title: form.model.isEmpty ? "Default model" : form.model) {
                                        ForEach(AppModel.models, id: \.self) { name in
                                            Button(name.isEmpty ? "Default model" : name) { form.model = name }
                                        }
                                    }
                                }
                            }
                            .frame(width: 210)
                        }
                        if form.kind == .orchestrator, let line = form.teamLine {
                            Text(line)
                                .font(Ledger.font(13))
                                .lineSpacing(3)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Ledger.bubble)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                HStack(spacing: 10) {
                    if let note = joinNote {
                        Text(note)
                            .font(Ledger.font(12))
                            .foregroundStyle(Ledger.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Cancel", action: close)
                        .buttonStyle(LedgerButtonStyle(height: 36))
                        .keyboardShortcut(.cancelAction)
                    Button(action: start) {
                        HStack(spacing: 6) {
                            if form.starting { Spinner(color: Ledger.onPrimary, size: 10) }
                            Text(startTitle)
                        }
                    }
                        .buttonStyle(LedgerButtonStyle(primary: true, height: 36))
                        .keyboardShortcut(.defaultAction)
                        .disabled(form.picked == nil || model.daemonDown || form.starting)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rule() }
                .padding(.top, 20)
            }
            .frame(width: 600)
            .foundryModal()
        }
        .onAppear {
            let request = model.newSession
            form.kind = request?.kind ?? .orchestrator
            if form.picked == nil { form.picked = request?.repo ?? model.selectedRepo ?? repos.first }
            loadBranches()
            loadTeams()
            // Without a repo there is no Create from; start at the name.
            if form.picked == nil { DispatchQueue.main.async { nameFocused = true } }
        }
        .onChange(of: form.picked) {
            loadBranches()
            loadTeams()
        }
        // Closed while the issue is read: nothing starts.
        .onDisappear { form.reading?.cancel() }
        .onExitCommand(perform: close)
    }

    private var namePlaceholder: String {
        switch form.choice {
        case .name(let text)?: text
        case .issue?: "optional; the issue names it"
        default: "optional"
        }
    }

    /// The Teams of the picked repo; the one shown stays when the new list has it.
    private func loadTeams() {
        let repo = form.picked
        model.loadTeams(repo: repo) { listed in
            guard form.picked == repo else { return }
            form.teams = listed
            form.team = TeamChoice.pick(from: listed, current: form.team, remembered: TeamChoice.remembered())
        }
    }

    private func loadBranches() {
        guard let repo = form.picked else { return }
        form.branches = []
        model.loadBranches(repo) { listed in
            guard form.picked == repo else { return }
            form.branches = listed.branches
            form.current = listed.current
            if !listed.branches.contains(where: { $0.name == form.base }) {
                form.base = listed.current.isEmpty ? listed.branches.first?.name ?? "" : listed.current
            }
        }
    }

    /// What a repo has running, for its row: "Orchestrator live", "Claude Code live", "stopped".
    private func status(_ repo: String) -> String? {
        let agents = model.agents(repo)
        if agents.contains(where: { $0.live && $0.isOrchestrator }) { return "Orchestrator live" }
        if agents.contains(where: { $0.live && $0.kind == .claude }) { return "Claude Code live" }
        return agents.isEmpty ? nil : "stopped"
    }

    /// When the picked repo already has Orchestrators, where the new agent goes.
    private var joinNote: String? {
        guard let repo = form.picked else { return nil }
        let count = model.agents(repo).filter { $0.isOrchestrator && $0.live }.count
        guard count > 0 else { return nil }
        let name = URL(fileURLWithPath: repo).lastPathComponent
        let newcomer = form.kind == .orchestrator ? "The new Orchestrator" : "Claude Code"
        return "\(name) already has \(count) Orchestrator\(count == 1 ? "" : "s"). \(newcomer) joins it as its own group; they all keep running."
    }

    private func choose() {
        guard let folder = model.chooseFolder() else { return }
        form.chosen.insert(folder, at: 0)
        form.picked = folder
    }

    private var startTitle: String {
        if form.starting { return form.choice.map { if case .issue = $0 { "Reading the issue…" } else { "Starting…" } } ?? "Starting…" }
        return form.kind == .orchestrator ? "Start Orchestrator" : "Start Claude Code"
    }

    /// Starts the agent where Create from says: the repo's checkout, a branch, or a new branch in
    /// its own worktree; from an issue, it reads the issue first and starts on it. A failure keeps
    /// the dialog open and says why.
    private func start() {
        guard let picked = form.picked, !form.starting else { return }
        let name = form.name.trimmingCharacters(in: .whitespaces)
        if let team = form.teamToOpen { TeamChoice.remember(team) }
        switch form.choice {
        case nil:
            model.open(repo: picked, kind: form.kind, name: name, model: form.model, team: form.teamToOpen)
            close()
        case .branch(let branch)?:
            launch(picked, name: name, branch: branch)
        case .newBranch(let branch)?:
            launch(picked, name: name, newBranch: branch)
        case .name(let text)?:
            launch(picked, name: name.isEmpty ? text : name, newBranch: fanoutBranch(text))
        case .issue(let typed)?:
            guard let reference = issueReference(typed) else {
                form.problem = "Type an issue number, like 12, or its link, like https://github.com/owner/repo/issues/12."
                return
            }
            form.starting = true
            form.reading = Task {
                do {
                    let issue = try await AppModel.fetchIssue(reference, in: picked)
                    guard !Task.isCancelled else { return }
                    launch(picked, name: name.isEmpty ? issue.name : name,
                           newBranch: fanoutBranch("\(issue.number) \(issue.title)"), request: issue.request)
                } catch {
                    form.starting = false
                    form.problem = "\(error)"
                }
            }
        }
    }

    private func launch(_ repo: String, name: String, branch: String? = nil, newBranch: String? = nil, request: String? = nil) {
        form.starting = true
        form.problem = nil
        model.open(repo: repo, kind: form.kind, name: name, model: form.model, team: form.teamToOpen, request: request,
                   branch: branch, newBranch: newBranch, base: newBranch == nil ? nil : form.base) { problem in
            form.starting = false
            if let problem { form.problem = problem } else { close() }
        }
    }

    private func close() {
        model.newSession = nil
    }
}

final class NewSessionForm: ObservableObject {
    @Published var kind: Agent.Kind = .orchestrator
    @Published var name = ""
    @Published var model = ""
    /// The Teams to pick from, and the one picked; nil until the daemon has listed them.
    @Published var teams: [Team] = []
    @Published var team: String?
    @Published var picked: String?
    /// Create from: which tab, and what is typed or picked there.
    @Published var tab: CreateFromTab = .smart
    @Published var from = ""
    @Published var pickedBranch: String?
    /// The picked repo's branches and its checked-out one; new branches start from `base`.
    @Published var branches: [RepoBranch] = []
    @Published var current = ""
    @Published var base = ""
    /// Why the agent could not start: an unreadable issue, a branch git refused.
    @Published var problem: String?
    /// True while the issue is read or the agent starts.
    @Published var starting = false
    /// Reading the issue to start from.
    var reading: Task<Void, Never>?

    /// Where the new agent works; nil means the repo's own checkout.
    var choice: CreateFrom? {
        let text = from.trimmingCharacters(in: .whitespaces)
        switch tab {
        case .smart: return smartCreateFrom(text, branches: branches.map(\.name))
        case .github: return text.isEmpty ? nil : .issue(text)
        case .branch: return branchCreateFrom(text, picked: pickedBranch, branches: branches.map(\.name))
        case .name: return text.isEmpty ? nil : .name(text)
        }
    }
    /// The Team the new agent starts with: an Orchestrator's pick, nothing for a Normal session.
    var teamToOpen: String? { kind == .orchestrator ? team : nil }

    /// Under the picker: the picked Team's summary, then why any other Team cannot be picked.
    var teamLine: String? {
        let lines = [teams.first { $0.name == team }?.summary]
            + teams.compactMap { team in team.problem.map { "\(team.name) cannot be used: \($0)" } }
        let text = lines.compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// Folders chosen with the open panel this time, listed first.
    @Published var chosen: [String] = []
}

/// The Team of a new Orchestrator, as a compact menu in the model's place. A Team with a problem
/// is listed, dimmed, and cannot be picked.
struct TeamPicker: View {
    @ObservedObject var form: NewSessionForm

    var body: some View {
        FieldMenu(title: form.team ?? "No Teams yet") {
            ForEach(form.teams) { team in
                Button(team.name) { form.team = team.name }.disabled(!team.usable)
            }
        }
        .disabled(form.teams.isEmpty)
    }
}

/// A menu drawn as Foundry's field: the choice in a 38 pt box in a 1 pt rule, with a chevron.
struct FieldMenu<Items: View>: View {
    let title: String
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 8) {
                Text(title).font(Ledger.font(14)).foregroundStyle(Ledger.ink).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Ledger.ink3)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
            .background(Ledger.field)
            .overlay(Rectangle().strokeBorder(Ledger.ink3, lineWidth: Ledger.hairline))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// A step's label in a modal: "01 / Mode", the number in ink and the rest muted, then a quiet note.
struct StepLabel: View {
    let number: Int
    let title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(String(format: "%02d", number)).foregroundStyle(Ledger.ink)
            Text(" / \(title)")
            if let note {
                Text(" " + note).font(Ledger.font(11)).tracking(0).textCase(nil)
            }
        }
        .font(Ledger.monoFont(11, .bold))
        .tracking(1.1)
        .textCase(.uppercase)
        .foregroundStyle(Ledger.ink3)
        .lineLimit(1)
        .fixedSize()
    }
}

/// The dimmed window behind a modal; a click on it closes the modal.
struct ModalBackdrop: View {
    let close: () -> Void

    var body: some View {
        Ledger.markerInk.opacity(0.38)
            .ignoresSafeArea()
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

/// A modal's head: a mono label, the title in the display face, a line under it, and a close box,
/// over a 2 pt ink rule.
struct ModalHead: View {
    let label: String
    let title: String
    var detail: String?
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(label)
                Text(title)
                    .font(Ledger.display(34))
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail).font(Ledger.font(14)).foregroundStyle(Ledger.ink3)
                }
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ledger.ink3)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
    }
}

extension View {
    /// Foundry's raised sheet (ui-ux/0113, ui-ux/0119): the sheet in a 2 pt ink frame casting a hard ink block
    /// down and right, never a blur.
    func foundryModal(offset: CGFloat = 8) -> some View {
        background(Ledger.paper)
            .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
            .background(Rectangle().fill(Ledger.cast).offset(x: offset, y: offset))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

/// A small caption above a field in a modal.
struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Ledger.font(12.5, .semibold))
            .foregroundStyle(Ledger.ink2)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
    }
}

/// One of the two ways to work, as a card you pick: a 1 pt rule, or picked a 2 pt ink frame casting
/// the accent's hard offset.
struct ModeCard: View {
    let kind: Agent.Kind
    let picked: Bool
    let title: String
    let detail: String
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AgentGlyph(kind: kind)
                    Text(title).font(Ledger.font(15, .bold))
                }
                Text(detail)
                    .font(Ledger.font(13))
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Ledger.ink)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ledger.paper)
            .overlay(Rectangle().strokeBorder(picked ? Ledger.ink : Ledger.rule, lineWidth: picked ? Ledger.ruleStrong : Ledger.hairline))
            .background { if picked { Rectangle().fill(Ledger.accent).offset(x: 4, y: 4) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// A repo to start in: its name and what runs there, a 40 pt row between 1 pt rules; picked, the
/// sunk fill with the accent's edge.
struct RepoChoice: View {
    let repo: String
    let status: String?
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        let info = SessionInfo(repo: repo, live: false)
        Button(action: pick) {
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(info.name).font(Ledger.font(14, picked ? .bold : .regular)).lineLimit(1)
                Spacer(minLength: 8)
                if let status {
                    Text(status).font(Ledger.monoFont(11)).foregroundStyle(Ledger.ink3)
                }
            }
            .foregroundStyle(Ledger.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(picked ? Ledger.selected : Color.clear)
            .overlay(alignment: .leading) { if picked { Rectangle().fill(Ledger.accent).frame(width: 3) } }
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(info.shortPath)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// Rename an Orchestrator or a Claude Code session.
struct RenameModal: View {
    @EnvironmentObject private var model: AppModel
    let agent: Agent
    @StateObject private var draft = Draft()
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            ModalBackdrop(close: close)
            VStack(alignment: .leading, spacing: 0) {
                ModalHead(label: agent.displayName, title: "Rename \(agent.isOrchestrator ? "Orchestrator" : "session")", close: close)
                    .padding(.bottom, 18)
                TextField(agent.displayName, text: $draft.text)
                    .textFieldStyle(.plain)
                    .ledgerField()
                    .focused($nameFocused)
                    .padding(.horizontal, 24)
                    .onSubmit(save)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: close)
                        .buttonStyle(.ledger)
                        .keyboardShortcut(.cancelAction)
                    Button("Rename", action: save)
                        .buttonStyle(.ledgerPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .frame(width: 420)
            .foundryModal()
        }
        .onAppear {
            if draft.text.isEmpty { draft.text = agent.name ?? "" }
            DispatchQueue.main.async { nameFocused = true }
        }
        .onExitCommand(perform: close)
    }

    private func save() {
        model.rename(agent.id, to: draft.text)
        close()
    }

    private func close() {
        model.renaming = nil
    }
}

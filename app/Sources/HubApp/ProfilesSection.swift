import AppKit
import Foundry
import HubCore
import SwiftUI

/// Settings' Profiles section (ui-ux/0145): the Profiles to pick from, and the editor for the one
/// picked. Profiles live in the daemon's files, so the section reads them fresh each time it opens.
/// The model is the app's own, not a view's, so edits not yet saved survive until the human is asked
/// about them (ui-ux/0103).
@MainActor
final class ProfileSettingsModel: ObservableObject {
    @Published var profiles: [WorkerProfile] = []
    /// The Teams the repo can use, for "Used by".
    @Published var teams: [Team] = []
    @Published var picked: String?
    @Published var form = ProfileForm()
    /// The role shows as a text field instead of as rendered Markdown (ui-ux/0149).
    @Published var editingRole = false
    /// The daemon's message about the last load, save, copy or delete.
    @Published var failure: String?
    @Published private(set) var saving = false
    /// The card that asks what to do with unsaved edits is up.
    @Published private(set) var asking = false
    /// What the human asks the drafting agent for (features/0101).
    @Published var request = ""
    /// The draft running, by the id its cancel names.
    @Published private(set) var drafting: String?
    /// The last draft's line and the form from before it, which Undo puts back.
    @Published private(set) var drafted: (note: String, before: ProfileForm)?
    /// The CLIs signed in, which the drafting agent can run on.
    @Published private(set) var signedIn: [String] = []
    /// The drafting agent, remembered on this Mac.
    @Published var drafterCli = UserDefaults.standard.string(forKey: "profileDrafterCli") ?? ProfileDrafter.defaultCli {
        didSet {
            UserDefaults.standard.set(drafterCli, forKey: "profileDrafterCli")
            if oldValue != drafterCli { drafterModel = "" }
        }
    }
    @Published var drafterModel = UserDefaults.standard.string(forKey: "profileDrafterModel") ?? ProfileDrafter.defaultModel {
        didSet { UserDefaults.standard.set(drafterModel, forKey: "profileDrafterModel") }
    }
    private var saved = ProfileForm()
    private var pending: (@MainActor () -> Void)?
    private let client = DaemonClient()
    var repo: String?
    /// The Profile to pick at the next read, from a Member's Edit in Profiles.
    var wanted: String?

    var profile: WorkerProfile? { profiles.first { $0.name == picked } }
    var changed: Bool { form != saved }
    var changeCount: Int { form.changeCount(from: saved) }
    var readOnly: Bool { form.readOnly }
    var canSave: Bool { !readOnly && changed && !saving && drafting == nil && picked != nil }
    /// Only yours and the repo's own files are deleted; Echo's are not.
    var canDelete: Bool { profile.map { $0.level == ProfileForm.yours || $0.level == ProfileForm.repo } == true }
    /// The Teams whose Members start from the picked Profile.
    var uses: [ProfileUse] { picked.map { ProfileUse.of($0, in: teams) } ?? [] }

    func refresh(select name: String? = nil, then done: (@MainActor () -> Void)? = nil) {
        let (client, repo) = (client, repo)
        run({ try client.providers() }) { providers in
            self.signedIn = providers.filter { $0.installed && $0.signedIn }.map(\.cli)
            self.drafterCli = ProfileDrafter.cli(remembered: self.drafterCli, signedIn: self.signedIn)
        }
        run({ (try client.profiles(repo: repo), try client.teams(repo: repo)) }) { profiles, teams in
            self.profiles = profiles
            self.teams = teams
            let want = name ?? self.wanted
            self.wanted = nil
            if let want, profiles.contains(where: { $0.name == want }) {
                if want != self.picked || !self.changed { self.pick(want) }
            } else if !profiles.contains(where: { $0.name == self.picked }) {
                self.pick(profiles.first?.name)
            } else if !self.changed {
                // Read fresh, unless the human has edits here.
                self.pick(self.picked)
            }
            done?()
        }
    }

    /// Picks a Profile in the list; unsaved edits are asked about first.
    func choose(_ name: String) {
        guard name != picked else { return }
        leave { self.pick(name) }
    }

    /// Runs `go` now, or after the human has answered the card when edits are not saved (ui-ux/0103).
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
            revert()
            go?()
        case .stay, .goOn:
            break
        }
    }

    private func pick(_ name: String?) {
        cancelDraft()
        drafted = nil
        picked = name
        failure = nil
        editingRole = false
        form = name.flatMap { name in profiles.first { $0.name == name } }.map(ProfileForm.init(profile:)) ?? ProfileForm()
        saved = form
    }

    /// Writes the Profile's file; `done` hears whether it was written, after the list is read again.
    func save(done: (@MainActor (Bool) -> Void)? = nil) {
        if let blocker = form.blocker {
            failure = blocker
            done?(false)
            return
        }
        guard canSave else {
            done?(false)
            return
        }
        let (client, form, repo) = (client, form, repo)
        saving = true
        run({ try client.profile("set", name: form.name, level: form.level, repo: repo, fields: form.fields) }, then: { _ in
            self.saving = false
            self.saved = self.form
            self.refresh(select: form.name) { done?(true) }
        }, otherwise: {
            self.saving = false
            done?(false)
        })
    }

    func revert() {
        failure = nil
        drafted = nil
        form = saved
    }

    /// Has the picked agent draft the Profile's fields from `request` (features/0101). The form
    /// takes them as unsaved edits; the form from before stays for Undo.
    func draft(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, drafting == nil, !readOnly, picked != nil else { return }
        let id = UUID().uuidString
        let before = form
        let (client, repo, cli, model) = (client, repo, drafterCli, drafterModel)
        let (fields, profileCli) = (form.draftForm, form.cli.isEmpty ? profile?.cli ?? "claude" : form.cli)
        drafting = id
        failure = nil
        run({
            try client.draftProfile(id: id, cli: cli, model: model, request: request, form: fields,
                                    profileCli: profileCli, tools: ProfileTools.all, repo: repo)
        }, then: { draft in
            guard self.drafting == id else { return }
            self.drafting = nil
            self.form = self.form.applying(draft)
            self.drafted = (draft.note, before)
            self.request = ""
        }, otherwise: {
            // A cancelled draft has already let go; its error is not news.
            if self.drafting == id { self.drafting = nil } else { self.failure = nil }
        })
    }

    /// Stops the running draft; the form stays as it was.
    func cancelDraft() {
        guard let id = drafting else { return }
        drafting = nil
        let client = client
        Task.detached { try? client.cancelDraft(id: id) }
    }

    /// Puts the form back as it was before the last draft.
    func undoDraft() {
        guard let before = drafted?.before else { return }
        form = before
        drafted = nil
    }

    /// Asks for a name and a level, writes a blank Profile with a short starter role, and picks it.
    func newProfile() {
        leave {
            self.askNameAndLevel(title: "New Profile", field: "code-reviewer",
                                 message: "Name it with lowercase letters, digits and -. Next, say what it should do.") { name, level in
                // Once this card has gone, so the next one takes the keyboard.
                DispatchQueue.main.async { self.askWhatItDoes(name, level: level) }
            }
        }
    }

    /// Asks for a name and a level and copies the picked Profile under it.
    func duplicate() {
        guard let source = picked else { return }
        leave {
            self.askNameAndLevel(title: "Duplicate \(source)", field: "name",
                                 message: "The copy is a Profile of its own; point a Team's Members at it to use it.",
                                 prefill: ProfileForm.copyName(of: source, taking: self.profiles.map(\.name))) { name, level in
                self.create(name, level: level, from: source)
            }
        }
    }

    /// Echo's own Profile, copied into yours or this repo's under the same name, which then replaces it.
    func makeCopy() {
        guard let name = picked else { return }
        askLevel(title: "Make my copy of \(name)",
                 message: "The copy replaces Echo's \(name) for every Team that starts from it.") { level in
            let (client, repo) = (self.client, self.repo)
            self.run({ try client.profile("copy", name: name, level: level, repo: repo) }) { _ in
                self.refresh(select: name)
            }
        }
    }

    /// Asks for a new name and renames the picked file (features/0103); the daemon moves the Members
    /// of your Teams and the repo's onto it, and its refusal shows in the bar.
    func rename() {
        guard let profile, canDelete, let level = profile.level else { return }
        leave {
            let question = FoundryQuestion("Rename \(profile.name)",
                                           message: "The Members of your Teams and this repo's that start from it move to the new name.",
                                           answers: [FoundryAnswer("Rename", role: .primary)], field: "name")
            FoundryAsk.shared.ask(question) { answer, text in
                guard answer == "Rename" else { return }
                let name = text.trimmingCharacters(in: .whitespaces)
                guard name != profile.name else { return }
                guard ProfileForm.validName(name) else {
                    self.failure = "A Profile name is 1 to 32 lowercase letters, digits and -, like code-reviewer."
                    return
                }
                let (client, repo) = (self.client, self.repo)
                self.run({ try client.profile("rename", name: profile.name, level: level, repo: repo, to: name) }) { _ in
                    self.saved = self.form
                    self.refresh(select: name)
                }
            }
            FoundryAsk.shared.text = profile.name
        }
    }

    /// Deletes the picked file; the daemon refuses while a Team's Member starts from it (features/0096),
    /// and its message shows in the bar.
    func delete() {
        guard let profile, canDelete, let level = profile.level else { return }
        let below = profile.replaces?.last
        let message = below.map { "Its file is deleted, and the \($0) one is used again." }
            ?? "Its file is deleted. A Team's Member that starts from it is refused, so Echo checks that none does."
        FoundryAsk.shared.confirm("Delete \(profile.name)?", message: message, answer: FoundryAnswer("Delete", role: .destructive)) {
            let (client, repo) = (self.client, self.repo)
            self.run({ try client.profile("delete", name: profile.name, level: level, repo: repo) }) { _ in
                self.saved = self.form
                self.refresh(select: below == nil ? nil : profile.name)
            }
        }
    }

    /// Opens the Profile's Markdown file in the human's editor.
    func openFile() {
        guard let path = profile?.path, !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// The last step of New Profile: what it should do, drafted by the agent picked under the role,
    /// or nothing for the blank starter. The file is written blank first either way (ui-ux/0146).
    private func askWhatItDoes(_ name: String, level: String) {
        let drafter = ProfileDrafter.label(cli: drafterCli, model: drafterModel,
                                           models: ModelCatalog.shared.models[drafterCli] ?? [])
        let question = FoundryQuestion("What should \(name) do?",
                                       message: "Say what it is for, what it needs and how it should work; \(drafter) drafts it, and you review it before saving. Leave it empty for the blank starter.",
                                       answers: [FoundryAnswer("Start blank"), FoundryAnswer("Draft with agent", role: .primary)],
                                       field: "a UX designer that checks every screen against our design system")
        FoundryAsk.shared.ask(question) { answer, text in
            guard let answer else { return }
            let request = answer == "Start blank" ? "" : text
            self.create(name, level: level, from: nil) { self.draft(request) }
        }
    }

    private func create(_ name: String, level: String, from source: String?, then: (@MainActor () -> Void)? = nil) {
        let (client, repo) = (client, repo)
        run({ try client.profile("new", name: name, level: level, repo: repo, from: source) }) { _ in
            self.refresh(select: name) {
                self.editingRole = source == nil
                then?()
            }
        }
    }

    /// A name and then a level; a name the daemon cannot take comes back as its refusal in the bar.
    private func askNameAndLevel(title: String, field: String, message: String, prefill: String = "",
                                 then: @escaping @MainActor (String, String) -> Void) {
        let question = FoundryQuestion(title, message: message, answers: levelAnswers, field: field)
        FoundryAsk.shared.ask(question) { answer, text in
            guard let level = self.level(for: answer) else { return }
            let name = text.trimmingCharacters(in: .whitespaces)
            guard ProfileForm.validName(name) else {
                self.failure = "A Profile name is 1 to 32 lowercase letters, digits and -, like code-reviewer."
                return
            }
            then(name, level)
        }
        if !prefill.isEmpty { FoundryAsk.shared.text = prefill }
    }

    private func askLevel(title: String, message: String, then: @escaping @MainActor (String) -> Void) {
        FoundryAsk.shared.ask(FoundryQuestion(title, message: message, answers: levelAnswers)) { answer, _ in
            if let level = self.level(for: answer) { then(level) }
        }
    }

    /// Yours, and This repo when a repo is selected; Return picks Yours.
    private var levelAnswers: [FoundryAnswer] {
        (repo == nil ? [] : [FoundryAnswer("This repo")]) + [FoundryAnswer("Yours", role: .primary)]
    }

    private func level(for answer: String?) -> String? {
        switch answer {
        case "Yours": ProfileForm.yours
        case "This repo": ProfileForm.repo
        default: nil
        }
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

/// Settings' Profiles section, laid out like Teams (ui-ux/0145, ui-ux/0121): the list with the
/// section's head on the left, the picked Profile's fields in the middle, and the bar with Save
/// under both.
struct ProfilesSection: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ProfilesList(profiles: profiles)
                    .frame(width: 232)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Ledger.desk)
                Rectangle()
                    .fill(Ledger.rule)
                    .frame(width: Ledger.hairline)
                    .frame(maxHeight: .infinity)
                ProfileEditorColumn(profiles: profiles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            ProfileSaveBar(profiles: profiles)
        }
    }
}

/// The section's head, then the Profiles the selected repo can use, grouped by where each comes
/// from; New Profile, Duplicate and Delete sit under the list.
private struct ProfilesList: View {
    @ObservedObject var profiles: ProfileSettingsModel

    private static let groups = [("Yours", ProfileForm.yours), ("This repo", ProfileForm.repo),
                                 ("Shipped by Echo", ProfileForm.builtIn)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsLabel("\(SettingsLook.number(.profiles)) / Settings", size: 11)
                Text(SettingsSection.profiles.title)
                    .font(Ledger.display(40))
                    .textCase(.uppercase)
                    .foregroundStyle(Ledger.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.groups, id: \.1) { title, level in
                        let listed = profiles.profiles.filter { ($0.level ?? ProfileForm.builtIn) == level }
                        if !listed.isEmpty {
                            SettingsLabel(title, size: 11)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 8)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(listed) { profile in
                                let picked = profile.name == profiles.picked
                                // The picked row wears the face being edited, before it is saved.
                                let face = picked ? profiles.form.face : profile.face ?? ""
                                ProfileRow(name: profile.name, face: face.isEmpty ? nil : face,
                                           about: profile.description, problem: profile.problem, unsaved: picked && profiles.changed, picked: picked) {
                                    profiles.choose(profile.name)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            VStack(alignment: .leading, spacing: 10) {
                Button("New Profile", action: profiles.newProfile)
                    .buttonStyle(SettingsButtonStyle(height: 38, fill: true))
                HStack(spacing: 16) {
                    Button("Duplicate", action: profiles.duplicate)
                        .disabled(profiles.picked == nil)
                        .help("Copy the picked Profile under a new name")
                    if profiles.canDelete {
                        Button("Rename", action: profiles.rename)
                            .help("Give it a new name; the Members of your Teams and this repo's that start from it follow")
                        Button("Delete", action: profiles.delete)
                    }
                }
                .buttonStyle(.ledgerLink)
                Text("A Profile is everything about a Worker but its place in a Team. Echo's own are read-only: make your copy to change one.")
                    .font(Ledger.font(12))
                    .lineSpacing(3)
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

/// An entry in the list, as the Teams list draws one (ui-ux/0121, ui-ux/0132).
private struct ProfileRow: View {
    let name: String
    let face: String?
    let about: String
    let problem: String?
    let unsaved: Bool
    let picked: Bool
    let pick: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: 10) {
                ProfileFace(face: face, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(Ledger.font(15, .bold))
                            .foregroundStyle(Ledger.ink)
                            .lineLimit(1)
                        if unsaved {
                            Rectangle().fill(Ledger.accent).frame(width: 7, height: 7)
                                .accessibilityLabel("Unsaved changes")
                        }
                        Spacer(minLength: 0)
                    }
                    if !about.isEmpty {
                        Text(about)
                            .font(Ledger.font(12))
                            .lineSpacing(3)
                            .foregroundStyle(Ledger.ink3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let problem {
                        Text(problem)
                            .font(Ledger.font(12))
                            .foregroundStyle(SettingsLook.problem)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(picked || hover.on ? Ledger.paper : .clear)
            .pickedEdge(picked)
            .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The picked Profile: its head, then every field in place as Foundry fields, the role as a large
/// text field, then who starts from it.
private struct ProfileEditorColumn: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHead(profiles: profiles)
            if profiles.picked == nil {
                EmptyNote(title: "No Profile", detail: "Make one with New Profile.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 18) {
                            Group {
                                ProfileAbout(profiles: profiles)
                                ProfileRuns(profiles: profiles)
                                ProfileToolList(profiles: profiles)
                                ProfileChoices(profiles: profiles)
                            }
                            .disabled(profiles.readOnly || profiles.drafting != nil)
                        }
                        .frame(width: 300, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 18) {
                            ProfileRole(profiles: profiles)
                                .disabled(profiles.readOnly || profiles.drafting != nil)
                            if !profiles.readOnly {
                                ProfileAgentBox(profiles: profiles)
                            }
                            ProfileUsedBy(profiles: profiles)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.never)
            }
        }
        .background(Ledger.paper)
    }
}

/// Where the Profile comes from as a badge, its name in display capitals, and its file.
private struct ProfileHead: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            if profiles.picked != nil {
                FacePicker(face: $profiles.form.face, enabled: !profiles.readOnly && profiles.drafting == nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingsLabel("Profile", size: 11)
                        .fixedSize()
                    if profiles.picked != nil { badge }
                }
                Text(profiles.picked ?? "Profiles")
                    .font(Ledger.display(40))
                    .textCase(.uppercase)
                    .foregroundStyle(Ledger.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if let profile = profiles.profile {
                VStack(alignment: .trailing, spacing: 6) {
                    if let path = profile.path {
                        Text(path)
                            .font(Ledger.monoFont(11))
                            .foregroundStyle(Ledger.ink3)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                    }
                    Button("Open file", action: profiles.openFile)
                        .buttonStyle(.ledgerLink)
                        .fixedSize()
                        .help("Opens its Markdown file in your editor")
                }
                .frame(maxWidth: 320, alignment: .trailing)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ledger.desk)
        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
    }

    private var badge: some View {
        let title: String
        switch profiles.form.level {
        case ProfileForm.builtIn: title = "Shipped"
        case ProfileForm.repo: title = "This repo"
        default: title = "Yours"
        }
        return Text(title)
            .font(Ledger.monoFont(11, .bold))
            .tracking(0.88)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(Ledger.desk)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Ledger.ink)
            .fixedSize()
    }
}

/// The description, and the Profile's problem when it cannot run here.
private struct ProfileAbout: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        if let problem = profiles.profile?.problem {
            InspectorNote(problem, problem: true)
        }
        InspectorField("Description") {
            TextField("Description", text: $profiles.form.description,
                      prompt: Text("One line: what this Worker does, for the Orchestrator"), axis: .vertical)
                .labelsHidden()
                .lineLimit(1...3)
                .squareField(.inspector)
        }
    }
}

/// Its own CLI, model and effort, which a Team's node or its Workers default replaces (features/0094).
private struct ProfileRuns: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        InspectorGroup("Runs with") {
            InspectorField("CLI") { CliPicker(title: "CLI", selection: $profiles.form.cli) }
            InspectorField("Model") {
                ModelPicker(title: "Model", cli: profiles.form.cli, selection: $profiles.form.model)
            }
            InspectorField("Effort") { EffortPicker(title: "Effort", selection: $profiles.form.effort) }
            InspectorNote("A Team's node, or its Workers default, replaces these three. Empty leaves them to your defaults.")
        }
    }
}

/// The tools as a checklist, the skills as a checklist of the ones its CLI has, and the context as
/// names with commas between.
private struct ProfileToolList: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        InspectorGroup("Tools") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(ProfileTools.all, id: \.self) { tool in
                    Checkbox(tool, isOn: Binding(
                        get: { profiles.form.tools.contains(tool) },
                        set: { on in profiles.form.tools = ProfileTools.toggled(profiles.form.tools, tool, on: on) }),
                             size: 13)
                }
            }
            InspectorNote(profiles.form.tools.isEmpty ? "None named: the Worker gets every tool of its CLI."
                          : "Only these, on Claude Code.")
            if let note = ProfileTools.note(tools: profiles.form.tools, cli: profiles.form.cli) {
                InspectorNote(note, problem: true)
            }
        }
        InspectorGroup("Skills and context") {
            InspectorField("Skills") { ProfileSkillList(profiles: profiles) }
            InspectorField("Context") {
                ListField(title: "Context", names: $profiles.form.context, prompt: "files read first, like CONTEXT.md")
            }
        }
    }
}

/// The skills of the Profile's CLI as a checklist (ui-ux/0147): grouped by where each comes from,
/// with its description under it, a filter once there are many, and the named ones the CLI lacks
/// kept checked under Not installed.
private struct ProfileSkillList: View {
    @ObservedObject var profiles: ProfileSettingsModel
    @ObservedObject private var catalog = SkillCatalog.shared
    @StateObject private var filter = Draft()

    /// The CLI it runs on here: its own, else what Teams and your defaults give it.
    private var cli: String {
        let own = profiles.form.cli
        return own.isEmpty ? profiles.profile?.cli ?? "claude" : own
    }

    var body: some View {
        let installed = catalog.skills[cli] ?? []
        let chosen = profiles.form.skills
        VStack(alignment: .leading, spacing: 12) {
            if installed.count > ProfileSkills.filterOver {
                TextField("Filter skills", text: $filter.text, prompt: Text("Filter \(installed.count) skills"))
                    .labelsHidden()
                    .squareField(.inspector)
            }
            ForEach(ProfileSkills.groups(installed: installed, chosen: chosen, filter: filter.text)) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(group.title, size: 10)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.rows) { row in
                        SkillRow(row: row, isOn: Binding(
                            get: { chosen.contains(row.name) },
                            set: { on in profiles.form.skills = ProfileSkills.toggled(profiles.form.skills, row.name, on: on) }),
                            use: { match in profiles.form.skills = ProfileSkills.replaced(profiles.form.skills, row.name, with: match) })
                    }
                }
            }
            if let failure = catalog.failure {
                InspectorNote("The skills could not be read: \(failure)", problem: true)
            } else if !catalog.loaded {
                InspectorNote("Reading the skills installed…")
            } else if installed.isEmpty {
                InspectorNote(ProfileSkills.none(cli: cli))
            } else {
                InspectorNote(chosen.isEmpty ? "None checked: its Worker is not pointed at any."
                              : "Its Worker is told to use these when they fit the Task.")
            }
        }
        .task(id: profiles.repo ?? "") { await catalog.load(repo: profiles.repo) }
    }
}

/// One skill: its checkbox, Not installed when its CLI lacks it, and its description under it.
/// A bare name the CLI lacks offers the one plugin skill by that name in its place.
private struct SkillRow: View {
    let row: ProfileSkills.Row
    @Binding var isOn: Bool
    let use: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Checkbox(row.name, isOn: $isOn, size: 13)
                if !row.installed {
                    Text("Not installed")
                        .font(Ledger.monoFont(10, .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(SettingsLook.problem)
                        .fixedSize()
                }
            }
            if let match = row.match {
                Button("Use \(match)") { use(match) }
                    .buttonStyle(.ledgerLink)
                    .fixedSize()
                    .padding(.leading, 28)
                    .help("Names the installed plugin skill instead, in the same place")
            }
            if !row.description.isEmpty {
                Text(row.description)
                    .font(Ledger.font(11))
                    .lineSpacing(2)
                    .foregroundStyle(Ledger.ink3)
                    .lineLimit(2)
                    .padding(.leading, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(row.installed ? row.description : "Its CLI has no skill by this name; the Worker is still told it.")
    }
}

/// Each CLI's skills for the repo, as the daemon lists them; read again each time the section shows.
@MainActor
final class SkillCatalog: ObservableObject {
    static let shared = SkillCatalog()
    @Published private(set) var skills: [String: [SkillOption]] = [:]
    @Published private(set) var loaded = false
    /// Why the last read failed, if it did.
    @Published private(set) var failure: String?
    private var repo: String?
    private let client = DaemonClient()

    func load(repo: String?) async {
        if repo != self.repo {
            self.repo = repo
            loaded = false
        }
        let client = client
        let result = await Task.detached { Result { try client.skills(repo: repo) } }.value
        guard repo == self.repo else { return }
        switch result {
        case .success(let skills):
            self.skills = skills
            failure = nil
        case .failure(let error):
            failure = "\(error)"
        }
        loaded = true
    }
}

/// Lessons, Writes and Worktree.
private struct ProfileChoices: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        InspectorGroup("Other choices") {
            VStack(alignment: .leading, spacing: 6) {
                Checkbox("Give it this repo's Lessons", isOn: $profiles.form.lessons, size: 14)
                InspectorNote("Off leaves the repo's Lessons out of its prompt; your Preferences stay.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Checkbox("Writes files", isOn: $profiles.form.writes, size: 14)
                InspectorNote("Its tries of a Task differ and are worth comparing.")
            }
            InspectorField("Worktree") {
                SquarePicker(selection: $profiles.form.worktree,
                             options: [("", "Not set"), ("current", "The current checkout"), ("new", "A new worktree")],
                             weight: .inspector, label: "Worktree")
                InspectorNote("A hint for the Orchestrator; not set leaves it to the Member's Action.")
            }
        }
    }
}

/// The role: what its Worker is told to be, after the Worker Contract. It reads as rendered
/// Markdown, and the pencil switches it to its text (ui-ux/0149).
private struct ProfileRole: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        let editing = profiles.editingRole && !profiles.readOnly
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                SettingsLabel("Role", size: 11)
                Spacer()
                if !profiles.readOnly {
                    RoleEditToggle(editing: $profiles.editingRole)
                }
            }
            if editing {
                TextField("Role", text: $profiles.form.role, prompt: Text("You are … Say what you do, in steps the Worker follows."),
                          axis: .vertical)
                    .labelsHidden()
                    .lineLimit(16...60)
                    .font(Ledger.monoFont(12))
                    .squareField(.inspector, mono: true)
            } else {
                RoleText(role: profiles.form.role, readOnly: profiles.readOnly)
            }
            InspectorNote("Markdown, put after the Worker Contract in its prompt.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The pencil that turns the role's text field on and off: a 26 pt square in a 1 pt rule, filled
/// in ink while editing.
private struct RoleEditToggle: View {
    @Binding var editing: Bool
    @StateObject private var hover = Flag()

    var body: some View {
        let label = editing ? "Stop editing the role" : "Edit the role"
        Button { editing.toggle() } label: {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(editing ? Ledger.paper : hover.on ? Ledger.ink : Ledger.ink3)
                .background(editing ? Ledger.ink : hover.on ? Ledger.wash : .clear)
                .overlay(Rectangle().strokeBorder(editing ? Ledger.ink : Ledger.rule, lineWidth: Ledger.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(editing ? .isSelected : [])
    }
}

/// The role drawn as a document, in the field's frame so the page does not jump on Edit.
private struct RoleText: View {
    let role: String
    let readOnly: Bool

    var body: some View {
        let blocks = parseMarkdown(role)
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text(readOnly ? "No role." : "No role yet. Press the pencil to write one.")
                    .font(Ledger.font(13))
                    .foregroundStyle(Ledger.ink3)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block, leading: 5, codeSize: 12)
                    .padding(.top, index == 0 ? 0 : MarkdownBlockView.gap(blocks[index - 1], block))
            }
        }
        .font(Ledger.font(13))
        .foregroundStyle(Ledger.ink)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: 1))
    }
}

/// Change with an agent (features/0101, ui-ux/0150): what to change, the agent that drafts it, and
/// once it lands, what it did with Undo. While it drafts, Cancel stands in for Ask agent.
private struct ProfileAgentBox: View {
    @ObservedObject var profiles: ProfileSettingsModel
    @ObservedObject private var catalog = ModelCatalog.shared

    var body: some View {
        let drafter = ProfileDrafter.label(cli: profiles.drafterCli, model: profiles.drafterModel,
                                           models: catalog.models[profiles.drafterCli] ?? [])
        InspectorField("Change with an agent") {
            TextField("Change with an agent", text: $profiles.request,
                      prompt: Text("Say what to change, like: stricter about tests, or add the design skills"),
                      axis: .vertical)
                .labelsHidden()
                .lineLimit(3...8)
                .squareField(.inspector)
                .disabled(profiles.drafting != nil)
            HStack(alignment: .center, spacing: 10) {
                Text("Drafts with")
                    .font(Ledger.font(12))
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize()
                SquarePicker(selection: $profiles.drafterCli,
                             options: (profiles.signedIn.isEmpty ? [profiles.drafterCli] : profiles.signedIn)
                                 .map { ($0, ProfileDrafter.name(of: $0)) },
                             weight: .inspector, label: "Drafting CLI")
                    .frame(width: 150)
                    .disabled(profiles.drafting != nil)
                ModelPicker(title: "Drafting model", cli: profiles.drafterCli, selection: $profiles.drafterModel,
                            unset: "Its default")
                    .frame(maxWidth: 200)
                    .disabled(profiles.drafting != nil)
                Spacer(minLength: 0)
                if profiles.drafting == nil {
                    Button("Ask agent") { profiles.draft(profiles.request) }
                        .buttonStyle(.settingsPrimary)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(profiles.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Drafts the change into the form; nothing is saved until you press Save. ⌘Return")
                }
            }
            if profiles.drafting != nil {
                HStack(spacing: 10) {
                    Spinner(size: 11)
                    Text("Drafting with \(drafter)…")
                        .font(Ledger.font(12))
                        .foregroundStyle(Ledger.ink2)
                    Spacer(minLength: 0)
                    Button("Cancel", action: profiles.cancelDraft)
                        .buttonStyle(.ledgerLink)
                        .fixedSize()
                }
            } else if let drafted = profiles.drafted {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(drafted.note)
                        .font(Ledger.font(12))
                        .foregroundStyle(Ledger.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Undo", action: profiles.undoDraft)
                        .buttonStyle(.ledgerLink)
                        .fixedSize()
                        .help("Puts the Profile back as it was before this draft")
                }
            } else {
                InspectorNote("It can change the description, tools, skills, context, writes and role, never what it runs on. You review it before saving.")
            }
        }
    }
}

/// The Teams and Members that start from the Profile, read-only (features/0096).
private struct ProfileUsedBy: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        InspectorGroup("Used by") {
            let uses = profiles.uses
            if uses.isEmpty {
                InspectorNote("No Team here has a Member that starts from it.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(uses, id: \.team) { use in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(use.team)
                                .font(Ledger.font(13, .bold))
                                .foregroundStyle(Ledger.ink)
                            Text(use.members.joined(separator: ", "))
                                .font(Ledger.monoFont(12))
                                .foregroundStyle(Ledger.ink2)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(use.origin == "shipped" ? "Shipped" : use.origin == "repo" ? "This repo" : "Yours")
                                .font(Ledger.monoFont(10))
                                .foregroundStyle(Ledger.ink3)
                                .textCase(.uppercase)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
                    }
                }
                .overlay(Rectangle().strokeBorder(Ledger.ink3, lineWidth: Ledger.hairline))
                InspectorNote("A Profile a Member starts from is not deleted. To rename one, duplicate it, point these Members at the copy, then delete it.")
            }
        }
    }
}

/// Names with commas between, handed over on Return and when the field is left, so a comma typed on
/// its way to the next name is not tidied away.
private struct ListField: View {
    let title: String
    @Binding var names: [String]
    let prompt: String
    @StateObject private var draft = Draft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft.text, prompt: Text(prompt))
            .labelsHidden()
            .squareField(.inspector)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: names) { if !focused { draft.text = CommaList.format(names) } }
            .onAppear { draft.text = CommaList.format(names) }
    }

    private func commit() {
        let parsed = CommaList.parse(draft.text)
        if parsed != names { names = parsed }
        draft.text = CommaList.format(parsed)
    }
}

/// The bar under the list and the Profile: how many edits are not saved, Revert and Save; Echo's own
/// Profile offers Make my copy in Save's place, and the daemon's refusal shows here.
private struct ProfileSaveBar: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        HStack(spacing: 14) {
            if profiles.changed && !profiles.readOnly {
                Rectangle().fill(Ledger.accent).frame(width: 9, height: 9)
            }
            status
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if profiles.readOnly {
                Button("Make my copy", action: profiles.makeCopy)
                    .buttonStyle(.settingsPrimary)
                    .disabled(profiles.picked == nil)
            } else {
                Button("Revert", action: profiles.revert)
                    .buttonStyle(.settings)
                    .disabled(!profiles.changed)
                Button(profiles.form.name.isEmpty ? "Save" : "Save \(profiles.form.name)") { profiles.save() }
                    .buttonStyle(.settingsPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!profiles.canSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Ledger.desk)
        .overlay(alignment: .top) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
    }

    @ViewBuilder
    private var status: some View {
        if let failure = profiles.failure {
            Text(failure)
                .font(Ledger.font(14))
                .foregroundStyle(SettingsLook.problem)
                .textSelection(.enabled)
        } else if profiles.readOnly {
            line("Echo's own Profile", "Make your copy to change it.")
        } else if profiles.changed {
            let count = profiles.changeCount
            line("\(count) unsaved \(count == 1 ? "change" : "changes")", "A Worker picks it up when it starts or resumes.")
        } else {
            line("Saved", "A Worker picks it up when it starts or resumes.")
        }
    }

    private func line(_ lead: String, _ rest: String) -> some View {
        Text("\(Text(lead).font(Ledger.font(14, .bold)).foregroundStyle(Ledger.ink))\(Text(" · \(rest)").font(Ledger.font(14)).foregroundStyle(Ledger.ink3))")
    }
}

/// The card that asks what to do with a Profile's edits that are not saved (ui-ux/0103).
struct UnsavedProfileModal: View {
    @ObservedObject var profiles: ProfileSettingsModel

    var body: some View {
        UnsavedEditsCard(asking: profiles.asking,
                         name: profiles.form.name.isEmpty ? "this Profile" : profiles.form.name,
                         answer: profiles.answer)
    }
}

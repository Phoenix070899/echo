import Foundry
import HubCore
import SwiftUI

/// The picked Member's fields. Each says where its value comes from, and Reset takes the Member's
/// own value out so the field follows the level below again. Every edit is in the Team's draft
/// until Save; only "Edit shared role…" reaches a file, the Profile's.
struct MemberInspector: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member

    private var profile: WorkerProfile? { teams.profile(named: member.profile) }
    private var setting: (RunSetting) -> MemberValue<String> {
        { teams.form.resolve($0, for: member, profile: profile, defaults: teams.defaults) }
    }

    var body: some View {
        Group {
            MemberIdentity(teams: teams, member: member, profile: profile)
            MemberRuns(teams: teams, member: member, setting: setting)
            MemberRole(teams: teams, member: member, profile: profile)
            MemberToolList(teams: teams, member: member, profile: profile, cli: setting(.cli).value)
            MemberLists(teams: teams, member: member, profile: profile)
            MemberChoices(teams: teams, member: member, profile: profile)
        }
        .disabled(teams.readOnly)
        MemberSharedRole(teams: teams, member: member, profile: profile)
    }
}

/// Name, Action and Profile: every Member has them, so there is nothing to fall back to.
private struct MemberIdentity: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        InspectorField("Name") {
            CommitField(title: "Name", value: member.id, prompt: "lowercase letters, digits and -",
                        focusRequest: teams.nameFocusRequest,
                        // Return in the name goes back to the tree, so the keys carry on from there.
                        done: { teams.treeFocusRequest += 1 }) { text in
                teams.renameMember(member.id, to: text)
                return teams.memberNotice == nil
            }
            if let notice = teams.memberNotice {
                InspectorNote(notice, problem: true)
            }
        }
        InspectorField("Action") {
            SquarePicker(selection: Binding(get: { member.action }, set: { teams.changeAction(member.id, to: $0) }),
                         options: Action.shipped.map { ($0.id, $0.title) } + [(Action.custom, "Custom")],
                         weight: .inspector, label: "Action")
        }
        InspectorField("Profile") {
            SquarePicker(selection: Binding(get: { member.profile },
                                            set: { name in teams.form.updateMember(member.id) { $0.profile = name } }),
                         options: teams.profileOptions(including: member.profile).map { ($0, $0) },
                         weight: .inspector, label: "Profile")
            if let offered = teams.form.offeredProfile(for: member.id) {
                HStack(alignment: .firstTextBaseline) {
                    InspectorNote("\(member.action) usually starts from \(offered).")
                    Button("Use \(offered)") { teams.form.updateMember(member.id) { $0.profile = offered } }
                        .buttonStyle(.ledgerLink)
                        .fixedSize()
                }
            }
            if profile == nil {
                InspectorNote("No Profile named \(member.profile) exists here. Pick another, or a Worker started from it will fail.", problem: true)
            } else if let problem = profile?.problem {
                InspectorNote(problem, problem: true)
            }
        }
    }
}

/// The instruction, added after the Profile's role or in place of it.
private struct MemberRole: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        InspectorField("Instruction") {
            TextField("Instruction", text: Binding(
                get: { member.instructions ?? "" },
                set: { text in teams.form.updateMember(member.id) { $0.instructions = text.isEmpty ? nil : text } }),
                      prompt: Text("What this Member should do or avoid, beyond its role"), axis: .vertical)
                .labelsHidden()
                .lineLimit(3...12)
                .squareField(.inspector)
            Checkbox("Replace the role", isOn: Binding(
                get: { member.replaceRole ?? false },
                set: { on in teams.form.updateMember(member.id) { $0.replaceRole = on ? true : nil } }), size: 14)
                .disabled(!member.isSet(.instructions) && member.replaceRole != true)
            SourceLine(text: member.instructionNote(roleOf: member.profile),
                       reset: member.isSet(.instructions) ? { teams.form.clearMember(member.id, .instructions) } : nil)
        }
    }
}

/// CLI, model and effort, which follow the order of features/0085.
private struct MemberRuns: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let setting: (RunSetting) -> MemberValue<String>

    var body: some View {
        let cli = setting(.cli)
        let model = setting(.model)
        let effort = setting(.effort)
        InspectorField("CLI") {
            CliPicker(title: "CLI", selection: text(\.cli), unset: "Not set")
            SourceLine(text: describe(cli, empty: "your default"), reset: reset(.cli))
        }
        InspectorField("Model") {
            TextField("Model", text: text(\.model),
                      prompt: Text(model.value.isEmpty ? TeamForm.modelHint(cli: cli.value) : model.value))
                .labelsHidden()
                .squareField(.inspector)
            SourceLine(text: describe(model, empty: "the CLI's own default"), reset: reset(.model))
        }
        InspectorField("Effort") {
            EffortPicker(title: "Effort", selection: text(\.effort), inherited: effort.isOwn ? nil : effort.value)
            SourceLine(text: describe(effort, empty: "the CLI's own"), reset: reset(.effort))
        }
    }

    /// A text choice of the Member, empty when it leaves the choice to the level below.
    private func text(_ key: WritableKeyPath<Team.Member, String?>) -> Binding<String> {
        Binding(
            get: { member[keyPath: key] ?? "" },
            set: { value in teams.form.updateMember(member.id) { $0[keyPath: key] = value.isEmpty ? nil : value } })
    }

    private func reset(_ field: MemberField) -> (() -> Void)? {
        member.isSet(field) ? { teams.form.clearMember(member.id, field) } : nil
    }

    /// "claude, from naruto"; "this Member" when it is the Member's own.
    private func describe(_ value: MemberValue<String>, empty: String) -> String {
        value.isOwn ? value.sourceText : "\(value.value.isEmpty ? empty : value.value), \(value.sourceText)"
    }
}

/// The tools as a checklist, and what the CLI makes of them.
private struct MemberToolList: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?
    let cli: String

    var body: some View {
        let tools = member.listValue(.tools, profile: profile)
        InspectorGroup("Tools") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(MemberTools.all, id: \.self) { tool in
                    Checkbox(tool, isOn: Binding(
                        get: { tools.value.contains(tool) },
                        set: { on in
                            teams.form.updateMember(member.id) { $0.tools = MemberTools.toggled(tools.value, tool, on: on) }
                        }), size: 13)
                }
            }
            SourceLine(text: tools.isOwn || !tools.value.isEmpty ? tools.sourceText : "none named, \(tools.sourceText)",
                       reset: member.isSet(.tools) ? { teams.form.clearMember(member.id, .tools) } : nil)
            if let note = MemberTools.note(tools: tools.value, cli: cli) {
                InspectorNote(note, problem: true)
            }
        }
    }
}

/// Skills and context: names with commas between, the Member's own list in place of the Profile's.
private struct MemberLists: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        InspectorGroup("Skills and context") {
            list("Skills", .skills, member.skills, prompt: "skill names")
            list("Context", .context, member.context, prompt: "files read first, like CONTEXT.md")
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ field: MemberField, _ own: [String], prompt: String) -> some View {
        let value = member.listValue(field, profile: profile)
        InspectorField(title) {
            CommitField(title: title, value: CommaList.format(own),
                        prompt: own.isEmpty && !value.value.isEmpty ? CommaList.format(value.value) : prompt) { text in
                let names = CommaList.parse(text)
                teams.form.updateMember(member.id) {
                    if field == .skills { $0.skills = names } else { $0.context = names }
                }
                return true
            }
            SourceLine(text: value.isOwn ? "\(value.sourceText), in place of \(member.profile)'s"
                           : "\(value.value.isEmpty ? "none, " : "")\(value.sourceText)",
                       reset: value.isOwn ? { teams.form.clearMember(member.id, field) } : nil)
        }
    }
}

/// Lessons, Writes and Worktree.
private struct MemberChoices: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        let lessons = member.lessonsValue
        let writes = member.writesValue(profile: profile)
        let worktree = member.worktreeValue()
        InspectorGroup("Other choices") {
            VStack(alignment: .leading, spacing: 6) {
                Checkbox("Give it this repo's Lessons", isOn: Binding(
                    get: { lessons.value },
                    set: { on in teams.form.updateMember(member.id) { $0.lessons = on ? nil : false } }), size: 14)
                SourceLine(text: lessons.sourceText, reset: lessons.isOwn ? { teams.form.clearMember(member.id, .lessons) } : nil)
            }
            VStack(alignment: .leading, spacing: 6) {
                Checkbox("Writes files", isOn: Binding(
                    get: { writes.value },
                    set: { on in
                        let inherited = profile?.writes ?? false
                        teams.form.updateMember(member.id) { $0.writes = on == inherited ? nil : on }
                    }), size: 14)
                SourceLine(text: "\(writes.sourceText); only tells the Orchestrator what to expect",
                           reset: writes.isOwn ? { teams.form.clearMember(member.id, .writes) } : nil)
            }
            InspectorField("Worktree") {
                SquarePicker(selection: Binding(
                    get: { member.worktree ?? "" },
                    set: { value in teams.form.updateMember(member.id) { $0.worktree = value.isEmpty ? nil : value } }),
                             options: [("", "Not set"), ("current", "The current checkout"), ("new", "A new worktree")],
                             weight: .inspector, label: "Worktree")
                SourceLine(text: worktree.isOwn ? worktree.sourceText : "\(worktree.value == "new" ? "a new worktree" : "the current checkout"), \(worktree.sourceText); a hint for the Orchestrator",
                           reset: worktree.isOwn ? { teams.form.clearMember(member.id, .worktree) } : nil)
            }
        }
    }
}

/// The Profile's own file, which every Team that uses the Profile reads.
private struct MemberSharedRole: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        InspectorGroup("Shared role") {
            Button("Edit shared role…") { teams.editRole(of: member.profile) }
                .buttonStyle(.settings)
                .disabled(profile == nil)
                .help("Opens \(member.profile)'s file in your editor; Echo's own is copied into yours first")
            InspectorNote("This changes \(member.profile) for every Team, not only this one. "
                          + "Its own CLI, model and effort are in that file, and apply when a Member leaves them out.")
        }
    }
}

/// One grey line under a field: where its value comes from, and Reset when the Member sets it.
private struct SourceLine: View {
    let text: String
    var reset: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            InspectorNote(text)
            if let reset {
                Button("Reset", action: reset)
                    .buttonStyle(.ledgerLink)
                    .fixedSize()
                    .help("Take this Member's own value out")
            }
        }
    }
}

/// A text field that hands its text over on Return and when it is left, not on every key: a comma
/// typed on its way to the next name must not be tidied away, and a name half typed is not an id.
/// `commit` says whether the text was taken; a refused one is put back once the field is left.
private struct CommitField: View {
    let title: String
    let value: String
    var prompt = ""
    /// Counts up each time something outside asks for this field to take the keyboard.
    var focusRequest = 0
    /// Runs after Return when the text was taken.
    var done: (() -> Void)?
    let commit: (String) -> Bool
    @StateObject private var draft = Draft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft.text, prompt: Text(prompt))
            .labelsHidden()
            .squareField(.inspector)
            .focused($focused)
            .onSubmit { if save() { done?() } }
            .onChange(of: focused) {
                if !focused {
                    save()
                    draft.text = value
                }
            }
            .onChange(of: value) { if !focused { draft.text = value } }
            .onChange(of: focusRequest) { focused = true }
            .onAppear { draft.text = value }
    }

    /// Whether the text is taken: it already is the value, or `commit` accepted it.
    @discardableResult
    private func save() -> Bool {
        guard draft.text != value else { return true }
        if commit(draft.text) { return true }
        if !focused { draft.text = value }
        return false
    }
}

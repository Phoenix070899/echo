import HubCore
import SwiftUI

/// The Team's Members as an indented list, one row each, and the button that adds a custom Worker.
/// The tree view takes this over (ui-ux/0102); until then the list is how a Member is picked.
struct MembersSection: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        Section("Members") {
            if teams.form.members.isEmpty {
                Text("This Team has no Members yet. A Worker can still be started by its Profile's name.")
                    .font(Ledger.font(11))
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TeamTree.rows(teams.form.members), id: \.member.id) { row in
                    MemberRow(row: row, picked: row.member.id == teams.selectedMember) {
                        teams.selectMember(row.member.id)
                    }
                }
            }
            HStack {
                Button("New custom Worker…", action: teams.newCustomWorker)
                    .disabled(teams.readOnly)
                    .help("Makes a Profile of your own and adds a Member on it")
                Spacer()
            }
            if let notice = teams.memberNotice {
                Text(notice)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A Member in the list: its id, then its Action and Profile in grey; the picked one is filled.
private struct MemberRow: View {
    let row: TeamTree.Row
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                Text(row.member.id)
                    .fontWeight(picked ? .medium : .regular)
                    .foregroundStyle(Ledger.ink)
                Text("\(row.member.action), \(row.member.profile)")
                    .font(Ledger.font(11))
                    .foregroundStyle(Ledger.ink3)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth - 1) * 18 + 8)
            .padding(.trailing, 8)
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
            MemberRole(teams: teams, member: member, profile: profile)
            MemberRuns(teams: teams, member: member, setting: setting)
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
        Section("Member") {
            CommitField(title: "Name", value: member.id, prompt: "lowercase letters, digits and -") { text in
                teams.renameMember(member.id, to: text)
                return teams.memberNotice == nil
            }
            Picker("Action", selection: Binding(
                get: { member.action }, set: { teams.changeAction(member.id, to: $0) })) {
                ForEach(Action.shipped) { Text($0.title).tag($0.id) }
                Text("Custom").tag(Action.custom)
            }
            Picker("Profile", selection: Binding(
                get: { member.profile }, set: { name in teams.form.updateMember(member.id) { $0.profile = name } })) {
                ForEach(teams.profileOptions(including: member.profile), id: \.self) { Text($0).tag($0) }
            }
            if let offered = teams.form.offeredProfile(for: member.id) {
                HStack {
                    Text("\(member.action) usually starts from \(offered).")
                        .font(Ledger.font(11))
                        .foregroundStyle(Ledger.ink3)
                    Spacer()
                    Button("Use \(offered)") { teams.form.updateMember(member.id) { $0.profile = offered } }
                        .buttonStyle(.ledgerLink)
                }
            }
            if profile == nil {
                Text("No Profile named \(member.profile) exists here. Pick another, or a Worker started from it will fail.")
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let problem = profile?.problem {
                Text(problem)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = teams.memberNotice {
                Text(notice)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
        Section("Instruction") {
            TextField("Instruction", text: Binding(
                get: { member.instructions ?? "" },
                set: { text in teams.form.updateMember(member.id) { $0.instructions = text.isEmpty ? nil : text } }),
                      prompt: Text("What this Member should do or avoid, beyond its role"), axis: .vertical)
                .labelsHidden()
                .lineLimit(3...12)
            Toggle("Replace the role", isOn: Binding(
                get: { member.replaceRole ?? false },
                set: { on in teams.form.updateMember(member.id) { $0.replaceRole = on ? true : nil } }))
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
        Section("Runs with") {
            CliPicker(title: "CLI", selection: text(\.cli), unset: "Not set")
            SourceLine(text: describe(cli, empty: "your default"), reset: reset(.cli))
            TextField("Model", text: text(\.model),
                      prompt: Text(model.value.isEmpty ? TeamForm.modelHint(cli: cli.value) : model.value))
            SourceLine(text: describe(model, empty: "the CLI's own default"), reset: reset(.model))
            EffortPicker(title: "Effort", selection: text(\.effort), unset: "Not set")
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
        Section("Tools") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(MemberTools.all, id: \.self) { tool in
                    Toggle(tool, isOn: Binding(
                        get: { tools.value.contains(tool) },
                        set: { on in
                            teams.form.updateMember(member.id) { $0.tools = MemberTools.toggled(tools.value, tool, on: on) }
                        }))
                        .toggleStyle(.checkbox)
                }
            }
            SourceLine(text: tools.isOwn || !tools.value.isEmpty ? tools.sourceText : "none named, \(tools.sourceText)",
                       reset: member.isSet(.tools) ? { teams.form.clearMember(member.id, .tools) } : nil)
            if let note = MemberTools.note(tools: tools.value, cli: cli) {
                Text(note)
                    .font(Ledger.font(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
        Section("Skills and context") {
            list("Skills", .skills, member.skills, prompt: "skill names")
            list("Context", .context, member.context, prompt: "files read first, like CONTEXT.md")
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ field: MemberField, _ own: [String], prompt: String) -> some View {
        let value = member.listValue(field, profile: profile)
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

/// Lessons, Writes and Worktree.
private struct MemberChoices: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        let lessons = member.lessonsValue
        let writes = member.writesValue(profile: profile)
        let worktree = member.worktreeValue()
        Section("Other choices") {
            Toggle("Give it this repo's Lessons", isOn: Binding(
                get: { lessons.value },
                set: { on in teams.form.updateMember(member.id) { $0.lessons = on ? nil : false } }))
            SourceLine(text: lessons.sourceText, reset: lessons.isOwn ? { teams.form.clearMember(member.id, .lessons) } : nil)
            Toggle("Writes files", isOn: Binding(
                get: { writes.value },
                set: { on in
                    let inherited = profile?.writes ?? false
                    teams.form.updateMember(member.id) { $0.writes = on == inherited ? nil : on }
                }))
            SourceLine(text: "\(writes.sourceText); only tells the Orchestrator what to expect",
                       reset: writes.isOwn ? { teams.form.clearMember(member.id, .writes) } : nil)
            Picker("Worktree", selection: Binding(
                get: { member.worktree ?? "" },
                set: { value in teams.form.updateMember(member.id) { $0.worktree = value.isEmpty ? nil : value } })) {
                Text("Not set").tag("")
                Text("The current checkout").tag("current")
                Text("A new worktree").tag("new")
            }
            SourceLine(text: worktree.isOwn ? worktree.sourceText : "\(worktree.value == "new" ? "a new worktree" : "the current checkout"), \(worktree.sourceText); a hint for the Orchestrator",
                       reset: worktree.isOwn ? { teams.form.clearMember(member.id, .worktree) } : nil)
        }
    }
}

/// The Profile's own file, which every Team that uses the Profile reads.
private struct MemberSharedRole: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member
    let profile: WorkerProfile?

    var body: some View {
        Section("Shared role") {
            HStack {
                Button("Edit shared role…") { teams.editRole(of: member.profile) }
                    .disabled(profile == nil)
                    .help("Opens \(member.profile)'s file in your editor; Echo's own is copied into yours first")
                Spacer()
            }
            Text("This changes \(member.profile) for every Team, not only this one. "
                 + "Its own CLI, model and effort are in that file, and apply when a Member leaves them out.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One grey line under a field: where its value comes from, and Reset when the Member sets it.
private struct SourceLine: View {
    let text: String
    var reset: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let reset {
                Button("Reset", action: reset)
                    .buttonStyle(.ledgerLink)
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
    let commit: (String) -> Bool
    @StateObject private var draft = Draft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft.text, prompt: Text(prompt))
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) {
                if !focused {
                    save()
                    draft.text = value
                }
            }
            .onChange(of: value) { if !focused { draft.text = value } }
            .onAppear { draft.text = value }
    }

    private func save() {
        guard draft.text != value else { return }
        if commit(draft.text) { return }
        if !focused { draft.text = value }
    }
}

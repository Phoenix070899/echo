import Foundry
import HubCore
import SwiftUI

/// The picked Member's fields (ui-ux/0145, features/0094): its id, Action, Profile, Hand-offs, and the
/// CLI, model and effort it runs on, each saying where its value comes from, with Reset to follow the
/// level below again. Every edit is in the Team's draft until Save. The rest of its Profile shows
/// read-only, with Edit in Profiles.
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
            MemberAfter(teams: teams, member: member)
            MemberRuns(teams: teams, member: member, setting: setting)
        }
        .disabled(teams.readOnly)
        MemberProfile(member: member, profile: profile, cli: setting(.cli).value)
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

/// The Hand-offs into the Member (features/0092, ui-ux/0144): one row per Member it comes after,
/// with an Automatic switch and Remove, then Add to draw one more, so a drag on the canvas is never
/// the only way. A line into a verify Member runs through --verify and has no switch.
private struct MemberAfter: View {
    @ObservedObject var teams: TeamSettingsModel
    let member: Team.Member

    var body: some View {
        InspectorField("After") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(member.handOffs, id: \.from) { handOff in
                    HStack(spacing: 10) {
                        Text(handOff.from == Team.orchestratorID ? "Orchestrator" : handOff.from)
                            .font(handOff.from == Team.orchestratorID ? Ledger.font(13) : Ledger.monoFont(12))
                            .foregroundStyle(Ledger.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if member.action == "verify" {
                            Text("via --verify")
                                .font(Ledger.monoFont(11))
                                .foregroundStyle(Ledger.ink3)
                        } else if handOff.from != Team.orchestratorID {
                            Checkbox("Automatic", isOn: Binding(
                                get: { handOff.auto },
                                set: { teams.setAutomatic($0, from: handOff.from, to: member.id) }), size: 12)
                                .fixedSize()
                                .help("The daemon starts this Member itself when that one ends done")
                        }
                        Button("Remove") { teams.disconnect(handOff.from, to: member.id) }
                            .buttonStyle(.ledgerLink)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
                }
                if member.handOffs.isEmpty {
                    Text("No Hand-off comes in: the Orchestrator cannot reach it.")
                        .font(Ledger.font(13))
                        .foregroundStyle(SettingsLook.problem)
                        .padding(10)
                        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
                }
                let sources = TeamGraph.sources(for: member.id, in: teams.form.members)
                MenuButton(label: "Add a Hand-off", entries: {
                    sources.map { id in
                        .item(id == Team.orchestratorID ? "The Orchestrator" : id) { teams.connect(id, to: member.id) }
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("+ Add a Hand-off")
                            .font(Ledger.font(13))
                            .foregroundStyle(sources.isEmpty ? Ledger.ink3 : Ledger.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sources.isEmpty)
            }
            .overlay(Rectangle().strokeBorder(Ledger.ink3, lineWidth: Ledger.hairline))
            InspectorNote("An automatic Hand-off starts this Member when that one ends done, with its Task and Final Report.")
        }
    }
}

/// CLI, model and effort, which follow the order of features/0094.
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
            ModelPicker(title: "Model", cli: cli.value, selection: text(\.model), unset: "Not set")
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

/// The rest of what the Worker is, from its Profile, read-only: one place edits it, Settings >
/// Profiles, and Edit in Profiles goes there with this Profile picked (ui-ux/0145).
private struct MemberProfile: View {
    @EnvironmentObject private var model: AppModel
    let member: Team.Member
    let profile: WorkerProfile?
    let cli: String

    var body: some View {
        InspectorGroup("From \(member.profile)") {
            if let profile {
                if !profile.description.isEmpty { fact("Description", profile.description) }
                fact("Tools", (profile.tools ?? []).isEmpty ? "every tool of its CLI" : CommaList.format(profile.tools ?? []))
                if let note = ProfileTools.note(tools: profile.tools ?? [], cli: cli) {
                    InspectorNote(note, problem: true)
                }
                fact("Skills", (profile.skills ?? []).isEmpty ? "none" : CommaList.format(profile.skills ?? []))
                fact("Context", (profile.context ?? []).isEmpty ? "none" : CommaList.format(profile.context ?? []))
                fact("Lessons", profile.lessons ?? true ? "in its prompt" : "left out")
                fact("Writes", profile.writes ? "yes" : "no")
                fact("Worktree", worktree(profile))
                if let role = profile.role, !role.isEmpty {
                    fact("Role", role, lines: 6)
                }
            }
            Button("Edit in Profiles") { model.showProfile(member.profile) }
                .buttonStyle(.settings)
                .disabled(profile == nil)
                .help("Opens Settings > Profiles on \(member.profile); a change there reaches every Team that starts from it")
            InspectorNote("Shared by every Member, in any Team, that starts from \(member.profile).")
        }
    }

    /// The Profile's hint, else the Action's (features/0094).
    private func worktree(_ profile: WorkerProfile) -> String {
        if let own = profile.worktree, !own.isEmpty { return own == "new" ? "a new worktree" : "the current checkout" }
        let action = Action.shipped.first { $0.id == member.action }?.worktree ?? "current"
        return "\(action == "new" ? "a new worktree" : "the current checkout"), from the \(member.action) Action"
    }

    private func fact(_ label: String, _ value: String, lines: Int = 3) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MonoLabel(label)
            Text(value)
                .font(Ledger.font(13))
                .foregroundStyle(Ledger.ink2)
                .lineLimit(lines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
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

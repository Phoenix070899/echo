import HubCore
import SwiftUI

/// Settings' Teams section, across the whole width beside the section list (ui-ux/0101): the list
/// of what can be picked on the left, and what is picked on the right.
struct TeamsSection: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TeamsList(teams: teams)
                .frame(width: 260)
                .frame(maxHeight: .infinity, alignment: .top)
            Rectangle()
                .fill(Ledger.rule)
                .frame(width: Ledger.hairline)
                .frame(maxHeight: .infinity)
            Form {
                switch teams.pane {
                case .defaults:
                    DefaultsSettings(agents: agents)
                    OrchestratorSettings(agents: agents)
                    AgentFailure(agents: agents)
                case .team:
                    TeamEditor(teams: teams)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // What a Team's rules fall back to may have changed under Defaults.
        .onChange(of: teams.pane) {
            if teams.pane == .team { teams.refresh() }
        }
    }
}

/// Defaults at the top, then the Teams the selected repo can use, each with where it
/// comes from; New, Duplicate and Delete sit under the list.
private struct TeamsList: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    TeamRow(name: "Defaults", label: nil, problem: nil, picked: teams.pane == .defaults) { teams.show(.defaults) }
                    Rectangle()
                        .fill(Ledger.rule)
                        .frame(height: Ledger.hairline)
                        .padding(.vertical, 6)
                    if teams.form.isNew {
                        TeamRow(name: teams.form.name.isEmpty ? "New Team" : teams.form.name, label: "not saved yet",
                                problem: nil, picked: teams.pane == .team) {}
                    }
                    ForEach(teams.teams) { team in
                        TeamRow(name: team.name, label: team.origin, problem: team.problem,
                                picked: teams.pane == .team && !teams.form.isNew && team.name == teams.picked) {
                            teams.choose(team.name)
                        }
                    }
                }
                .padding(8)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("New Team", action: teams.newTeam)
                    Button("Duplicate", action: teams.duplicate)
                        .disabled(teams.form.isNew || teams.team == nil)
                    Spacer(minLength: 0)
                    if teams.canDelete {
                        Button("Delete…", action: teams.delete)
                    }
                }
                .buttonStyle(.ledger)
                Text("A Team sets what an Orchestrator and its Workers run with. It applies when an Orchestrator starts or resumes. Echo's own Teams cannot be changed: duplicate one to make it yours.")
                    .font(Ledger.font(11))
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }
}

/// An entry in the list: flat, 30 pt at least, the picked one on the selected fill, and its problem
/// under it where it has one.
private struct TeamRow: View {
    let name: String
    let label: String?
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
                    if let label {
                        Text(label)
                            .font(Ledger.font(11))
                            .foregroundStyle(Ledger.ink3)
                    }
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

/// The card that asks what to do with edits that are not saved: Return saves, Esc cancels
/// (ui-ux/0103, ui-ux/0006).
struct UnsavedTeamModal: View {
    @ObservedObject var teams: TeamSettingsModel
    @FocusState private var focused: Bool

    var body: some View {
        if teams.asking {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { teams.answer(.cancel) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Save changes to \(teams.form.name.isEmpty ? "this Team" : teams.form.name)?")
                        .font(Ledger.font(18, .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    Text("Your changes are not saved yet. Discard drops them.")
                        .font(Ledger.font(13))
                        .foregroundStyle(Ledger.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Discard") { teams.answer(.discard) }
                            .buttonStyle(.ledger)
                        Button("Cancel") { teams.answer(.cancel) }
                            .buttonStyle(.ledger)
                            .keyboardShortcut(.cancelAction)
                        Button("Save") { teams.answer(.save) }
                            .buttonStyle(.ledgerPrimary)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .frame(width: 420)
                .background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
                // A hairline, not a shadow, sets it apart from the dimmed window.
                .overlay(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous).strokeBorder(Ledger.rule))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
            // Focus leaves the page, so Esc and Return reach the card and not the page's keys.
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { DispatchQueue.main.async { focused = true } }
            .onExitCommand { teams.answer(.cancel) }
        }
    }
}

import HubCore
import SwiftUI

/// Settings' Teams section, across the whole width beside the section list (ui-ux/0101, laid out
/// as ui-ux/0121 says): the list of Teams with the section's head on the left, the picked Team's
/// tree in the middle, the inspector of the picked row on the right, and the bar with Save under
/// all three columns.
struct TeamsSection: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var agents: AgentSettingsModel

    var body: some View {
        // The bar with Save runs under all three columns, as Foundry's artboard has it.
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                TeamsList(teams: teams)
                    .frame(width: 232)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Ledger.desk)
                Rectangle()
                    .fill(Ledger.rule)
                    .frame(width: Ledger.hairline)
                    .frame(maxHeight: .infinity)
                switch teams.pane {
                case .defaults:
                    DefaultsPane(agents: agents)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .team:
                    TeamTreeColumn(teams: teams)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Rectangle()
                        .fill(Ledger.rule)
                        .frame(width: Ledger.hairline)
                        .frame(maxHeight: .infinity)
                    TeamInspectorColumn(teams: teams)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            if teams.pane == .team {
                TeamSaveBar(teams: teams)
            }
        }
        // What a Team's rules fall back to may have changed under Defaults.
        .onChange(of: teams.pane) {
            if teams.pane == .team { teams.refresh() }
        }
    }
}

/// The section's head, Defaults, then the Teams the selected repo can use, grouped by where each
/// comes from; New Team, Duplicate and Delete sit under the list (ui-ux/0099).
private struct TeamsList: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var teams: TeamSettingsModel

    private static let groups = [("Yours", "user"), ("This repo", "repo"), ("Shipped by Echo", "shipped")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsLabel("\(SettingsLook.number(.teams)) / Settings", size: 11)
                Text(SettingsSection.teams.title)
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
                    TeamRow(name: "Defaults", about: "What every agent starts with, and the Orchestrators' rules",
                            problem: nil, unsaved: false, picked: teams.pane == .defaults) { teams.show(.defaults) }
                    ForEach(Self.groups, id: \.1) { title, origin in
                        let listed = teams.teams.filter { $0.origin == origin }
                        let fresh = teams.form.isNew && teams.form.level == origin
                        if fresh || !listed.isEmpty {
                            SettingsLabel(title, size: 11)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 8)
                                .accessibilityAddTraits(.isHeader)
                            if fresh {
                                TeamRow(name: teams.form.name.isEmpty ? "New Team" : teams.form.name, about: "Not saved yet",
                                        problem: nil, unsaved: true, picked: teams.pane == .team) {}
                            }
                            ForEach(listed) { team in
                                let picked = teams.pane == .team && !teams.form.isNew && team.name == teams.picked
                                TeamRow(name: team.name, about: team.description, problem: team.problem,
                                        unsaved: picked && teams.changed, picked: picked) {
                                    teams.choose(team.name)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            VStack(alignment: .leading, spacing: 10) {
                Button("New Team") { model.newTeamShown = true }
                    .buttonStyle(SettingsButtonStyle(height: 38, fill: true))
                HStack(spacing: 16) {
                    Button("Duplicate", action: teams.duplicate)
                        .disabled(teams.form.isNew || teams.team == nil)
                        .help("Copy the picked Team under a new name; nothing is written until you save")
                    if teams.canDelete {
                        Button("Delete…", action: teams.delete)
                    }
                }
                .buttonStyle(.ledgerLink)
                Text("A Team applies when an Orchestrator starts or resumes. Echo's own Teams are read-only: duplicate one to change it.")
                    .font(Ledger.font(12))
                    .lineSpacing(3)
                    .foregroundStyle(Ledger.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

/// An entry in the list: the name in bold over its one line of description, over a 1 pt rule; the
/// picked one on the sheet's grey with no square (ui-ux/0132), a square accent dot while it has
/// edits not saved, and its problem in red under it where it has one.
private struct TeamRow: View {
    let name: String
    let about: String?
    let problem: String?
    let unsaved: Bool
    let picked: Bool
    let pick: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: pick) {
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
                if let about, !about.isEmpty {
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
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The list has no squares, so picked or hovered only the fill changes (ui-ux/0132).
            .background(picked || hover.on ? Ledger.paper : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The bar under the list, the tree and the inspector: how many edits are not saved, Revert and Save; a
/// shipped Team offers Duplicate in Save's place (ui-ux/0100), and the daemon's refusal shows here.
private struct TeamSaveBar: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        HStack(spacing: 14) {
            if teams.changed && !teams.readOnly {
                Rectangle().fill(Ledger.accent).frame(width: 9, height: 9)
            }
            status
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if teams.readOnly {
                Button("Duplicate", action: teams.duplicate)
                    .buttonStyle(.settingsPrimary)
            } else {
                Button("Revert", action: teams.revert)
                    .buttonStyle(.settings)
                    .disabled(!teams.changed)
                // Return renames in the tree, so Save gives up the key while the tree has it.
                Button(teams.form.name.isEmpty ? "Save" : "Save \(teams.form.name)") { teams.save() }
                    .buttonStyle(.settingsPrimary)
                    .keyboardShortcut(teams.treeFocused ? nil : .defaultAction)
                    .disabled(!teams.canSave)
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
        if let failure = teams.failure {
            Text(failure)
                .font(Ledger.font(14))
                .foregroundStyle(SettingsLook.problem)
                .textSelection(.enabled)
        } else if teams.readOnly {
            line("Echo's own Team", "Duplicate it to change it.")
        } else if teams.changed {
            let count = teams.changeCount
            line("\(count) unsaved \(count == 1 ? "change" : "changes")",
                 "An Orchestrator picks it up when it starts or resumes.")
        } else {
            line("Saved", "An Orchestrator picks it up when it starts or resumes.")
        }
    }

    private func line(_ lead: String, _ rest: String) -> some View {
        (Text(lead).font(Ledger.font(14, .bold)).foregroundStyle(Ledger.ink)
            + Text(" · \(rest)").font(Ledger.font(14)).foregroundStyle(Ledger.ink3))
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
                        .font(Ledger.font(18, .bold))
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
                            .buttonStyle(.settings)
                        Button("Cancel") { teams.answer(.cancel) }
                            .buttonStyle(.settings)
                            .keyboardShortcut(.cancelAction)
                        Button("Save") { teams.answer(.save) }
                            .buttonStyle(.settingsPrimary)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .frame(width: 420)
                .background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
                // A hairline, not a shadow, sets it apart from the dimmed window.
                .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
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

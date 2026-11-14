import HubCore
import SwiftUI

/// What the New Team sheet holds while it is open; the decisions on it are `NewTeamSheet`'s.
final class NewTeamDraft: ObservableObject {
    @Published var sheet = NewTeamSheet()
}

/// New Team: a modal in the middle of the window over a dimmed backdrop (ui-ux/0006). Name it, say
/// where it is kept, pick what it starts with and which provider runs it; Create opens the Team in
/// the Teams section, unsaved, with its tree showing.
struct NewTeamModal: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var teams: TeamSettingsModel
    /// Local state as an ObservableObject: the command-line tools lack the plugin `@State` needs.
    @StateObject private var draft = NewTeamDraft()
    @FocusState private var nameFocused: Bool

    private var hasRepo: Bool { teams.repo != nil }

    private var problem: String? { draft.sheet.problem(teams: teams.teams, hasRepo: hasRepo) }

    private var canCreate: Bool { draft.sheet.canCreate(teams: teams.teams, hasRepo: hasRepo) && !teams.asking }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Team")
                        .font(Ledger.font(20, .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("A Team sets what an Orchestrator and its Workers run with. You can change all of it afterwards.")
                        .foregroundStyle(Ledger.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

                nameField
                if hasRepo { keepIn }
                startingPoints
                if draft.sheet.offersProvider { provider }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: close)
                        .buttonStyle(.ledger)
                        .keyboardShortcut(.cancelAction)
                    Button("Create", action: create)
                        .buttonStyle(.ledgerPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 22)
            }
            .frame(width: 520)
            .background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            // A hairline, not a shadow, sets it apart from the dimmed window.
            .overlay(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous).strokeBorder(Ledger.rule))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
        // The card that asks about unsaved edits may have taken the keyboard; the name takes it back.
        .onReceive(teams.$asking) { asking in
            if !asking { DispatchQueue.main.async { nameFocused = true } }
        }
        .onExitCommand(perform: close)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Name")
            TextField("lowercase letters, digits and -", text: $draft.sheet.name)
                .textFieldStyle(.plain)
                .ledgerField()
                .focused($nameFocused)
                .padding(.horizontal, 24)
                .onSubmit(create)
            if let problem {
                Text(problem)
                    .font(Ledger.font(12))
                    .foregroundStyle(Ledger.fail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }
        }
    }

    private var keepIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Keep in")
                .padding(.top, 16)
            FlatSegmented(selection: $draft.sheet.level, options: [
                (TeamForm.userLevel, "Yours"),
                (TeamForm.repoLevel, "This repo"),
            ])
            .padding(.horizontal, 24)
            Text(draft.sheet.level(hasRepo: hasRepo) == TeamForm.repoLevel
                 ? "Saved in .echo/teams of this repo."
                 : "Saved in ~/.echo/teams, for every repo.")
                .font(Ledger.font(12))
                .foregroundStyle(Ledger.ink3)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    private var startingPoints: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Starting point")
                .padding(.top, 16)
            StartingPoints(draft: draft, starts: NewTeamSheet.starts(teams: teams.teams))
                .padding(.horizontal, 24)
            if draft.sheet.start == .copy {
                HStack(spacing: 8) {
                    Text("Copy of")
                        .font(Ledger.font(12.5, .semibold))
                        .foregroundStyle(Ledger.ink2)
                    Picker("Copy of", selection: copySource) {
                        ForEach(teams.teams) { team in
                            Text("\(team.name), \(team.origin)").tag(team.name)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }
        }
    }

    /// The Team a copy starts from: the one picked, else the first.
    private var copySource: Binding<String> {
        Binding(get: { draft.sheet.source(in: teams.teams)?.name ?? "" },
                set: { draft.sheet.copyOf = $0 })
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Provider")
                .padding(.top, 16)
            FlatSegmented(selection: $draft.sheet.preset,
                          options: ProviderPreset.allCases.map { ($0, $0.title) })
                .padding(.horizontal, 24)
        }
    }

    /// Opens the Team in the Teams section, unsaved, then closes the sheet. Unsaved edits of the
    /// Team shown there are asked about first (ui-ux/0103), and the sheet waits for the answer.
    private func create() {
        guard canCreate, let form = draft.sheet.form(teams: teams.teams, hasRepo: hasRepo) else { return }
        teams.startNew(form) { model.newTeamShown = false }
    }

    private func close() {
        model.newTeamShown = false
    }
}

/// The starting points as cards, one plain line each. Up and Down move the pick while the list has
/// the keyboard; a click picks one too.
private struct StartingPoints: View {
    @ObservedObject var draft: NewTeamDraft
    let starts: [NewTeamStart]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            ForEach(starts, id: \.self) { start in
                StartCard(start: start, picked: draft.sheet.start == start, focused: focused) {
                    draft.sheet.start = start
                    focused = true
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.isEmpty,
                  let next = NewTeamSheet.step(draft.sheet.start, in: starts, by: press.key == .downArrow ? 1 : -1)
            else { return .ignored }
            draft.sheet.start = next
            return .handled
        }
        .accessibilityLabel("Starting point")
    }
}

private struct StartCard: View {
    let start: NewTeamStart
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(picked ? Ledger.ink : Ledger.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(start.title).fontWeight(.medium)
                    Text(start.summary)
                        .font(Ledger.font(12.5))
                        .foregroundStyle(Ledger.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? (focused ? Ledger.chosen : Ledger.selected) : Ledger.wash,
                        in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// A segmented control made of fills only: a grey track, the picked choice on a lighter fill, no
/// shadow (ui-ux/0013). Left and Right move the pick while it has the keyboard.
struct FlatSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button {
                    selection = option.0
                    focused = true
                } label: {
                    Text(option.1)
                        .font(Ledger.font(12, on ? .medium : .regular))
                        .foregroundStyle(on ? Ledger.ink : Ledger.ink2)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(on ? (focused ? Ledger.chosen : Ledger.field) : .clear,
                                    in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Ledger.bubble, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let values = options.map(\.0)
            guard press.modifiers.isEmpty,
                  let next = NewTeamSheet.step(selection, in: values, by: press.key == .rightArrow ? 1 : -1)
            else { return .ignored }
            selection = next
            return .handled
        }
    }
}

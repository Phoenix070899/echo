import HubCore
import SwiftUI

/// Where Create from looks: anything (Smart), a GitHub issue, an existing branch, or a name for a
/// new branch.
enum CreateFromTab: CaseIterable, Identifiable {
    case smart, github, branch, name

    var id: Self { self }

    var title: String {
        switch self {
        case .smart: "Smart"
        case .github: "GitHub"
        case .branch: "Branch"
        case .name: "Name"
        }
    }

    var placeholder: String {
        switch self {
        case .smart: "Type a name, #1234, a branch, or a GitHub issue link"
        case .github: "An issue number, like 1234, or its link"
        case .branch: "Find a branch, or name a new one"
        case .name: "A name for the new branch, like Magic link login"
        }
    }
}

/// Create from, in the Start a session dialog: an agent can work on its own branch in its own
/// worktree, so several Orchestrators work on different features without touching each other's
/// files. Left empty, the agent works in the repo's own checkout.
struct CreateFromSection: View {
    @ObservedObject var form: NewSessionForm
    let submit: () -> Void
    @FocusState private var fieldFocused: Bool
    @StateObject private var baseSearch = BaseSearch()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                StepLabel(number: 3, title: "Create from", note: "(optional)")
                Spacer(minLength: 8)
                // Where it looks, as Foundry's segmented choice (ui-ux/0112).
                HStack(spacing: 0) {
                    ForEach(CreateFromTab.allCases) { tab in
                        Button {
                            form.tab = tab
                            form.problem = nil
                            if tab == .branch { form.from = "" }
                            fieldFocused = true
                        } label: {
                            SegmentLabel(title: tab.title, on: form.tab == tab, large: false)
                                .frame(height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(form.tab == tab ? .isSelected : [])
                    }
                }
                .segmentTrack()
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ledger.ink3)
                    TextField(form.tab.placeholder, text: $form.from)
                        .textFieldStyle(.plain)
                        .font(Ledger.font(14))
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(submit)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Ledger.field)
                .overlay(Rectangle().strokeBorder(fieldFocused ? Ledger.ink : Ledger.ink3, lineWidth: Ledger.hairline))
                basePicker
            }
            .padding(.top, 8)
            .onChange(of: form.from) {
                form.problem = nil
                if form.tab == .branch, form.pickedBranch != form.from { form.pickedBranch = nil }
            }

            if form.tab == .branch {
                branchList.padding(.top, 6)
            }

            if let problem = form.problem {
                note(problem, color: Ledger.failInk)
            } else if let (text, warn) = summary {
                note(text, color: warn ? Ledger.failInk : Ledger.ink2)
            }
        }
        // Where the dialog starts typing, as Orca's does; after the terminal lets go of the keyboard.
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
    }

    /// New branches start from this branch; a repo has many, so it is a search, not a menu.
    private var basePicker: some View {
        Button { baseSearch.shown = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .semibold))
                Text(form.base.isEmpty ? "HEAD" : form.base)
                    .font(Ledger.monoFont(12))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Ledger.ink3)
            }
            .foregroundStyle(Ledger.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(Rectangle().strokeBorder(Ledger.ink3, lineWidth: Ledger.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("New branches start from \(form.base.isEmpty ? "the repo's checkout" : form.base)")
        .accessibilityLabel("Start new branches from \(form.base)")
        .foundryPopover(isPresented: $baseSearch.shown, width: 340) {
            BaseBranchSearch(branches: form.branches.map(\.name), base: form.base, search: baseSearch) { name in
                form.base = name
                baseSearch.shown = false
                fieldFocused = true
            }
        }
    }

    private var branchList: some View {
        let text = form.from.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = form.branches.filter { text.isEmpty || $0.name.lowercased().contains(text) }.prefix(5)
        return VStack(spacing: 2) {
            if shown.isEmpty {
                Group {
                    if form.branches.isEmpty {
                        Pending("Reading branches…")
                    } else {
                        Text(text.isEmpty ? "No branches." : "No branch matches; Return makes a new one.")
                    }
                }
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            ForEach(Array(shown)) { branch in
                Button {
                    form.pickedBranch = branch.name
                    form.from = branch.name
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: form.pickedBranch == branch.name ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(form.pickedBranch == branch.name ? Ledger.ink : Ledger.ink3)
                        Text(branch.name)
                            .font(Ledger.monoFont(12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(place(of: branch))
                            .font(Ledger.font(12))
                            .foregroundStyle(Ledger.ink3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(form.pickedBranch == branch.name ? Ledger.selected : Color.clear)
                    .overlay(alignment: .leading) { ListMarker(picked: form.pickedBranch == branch.name).padding(.leading, 2) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowHover()
                .accessibilityAddTraits(form.pickedBranch == branch.name ? .isSelected : [])
            }
        }
    }

    private func place(of branch: RepoBranch) -> String {
        if let agent = branch.agent { return "a\(agent) works here" }
        if branch.name == form.current { return "the repo's checkout" }
        return branch.checkout == nil ? "" : "has a worktree"
    }

    /// What will happen, and whether it needs a second look.
    private var summary: (String, Bool)? {
        let base = form.base.isEmpty ? "the repo's checkout" : form.base
        switch form.choice {
        case nil:
            return form.tab == .branch
                ? ("Pick a branch or type a new one; left empty, it works in the repo's checkout.", false)
                : ("Empty: it works in the repo's checkout\(form.current.isEmpty ? "" : " of \(form.current)").", false)
        case .issue(let typed)?:
            guard issueReference(typed) != nil else {
                return ("Type an issue number, like 12, or its link.", true)
            }
            return ("Reads the issue, then works on a new branch from \(base) in its own worktree.", false)
        case .branch(let name)?:
            return existing(name)
        case .newBranch(let name)?:
            return ("No branch \(name) yet. Works on a new branch \(name) from \(base), in its own worktree.", false)
        case .name(let text)?:
            let branch = fanoutBranch(text)
            if form.branches.contains(where: { $0.name == branch }) {
                let (text, warn) = existing(branch)
                return ("\(branch) already exists. " + text, warn)
            }
            return ("Works on a new branch \(branch) from \(base), in its own worktree.", false)
        }
    }

    /// Where an agent on existing branch `name` works: wherever the branch is checked out.
    private func existing(_ name: String) -> (String, Bool) {
        let branch = form.branches.first { $0.name == name }
        if let agent = branch?.agent {
            return ("a\(agent) already works on \(name); both would change the same files.", true)
        }
        if name == form.current { return ("Works in the repo's checkout, on \(name).", false) }
        return branch?.checkout == nil
            ? ("Works on \(name) in a new worktree.", false)
            : ("Works on \(name) in its worktree.", false)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Ledger.font(12))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.top, 6)
    }
}

final class BaseSearch: ObservableObject {
    @Published var shown = false
    @Published var query = ""
    @Published var picked = 0
}

/// The base-branch picker in Foundry's popover (ui-ux/0125): a search field over the repo's
/// branches; ↑ and ↓ move, Return picks, Escape or a click outside closes.
private struct BaseBranchSearch: View {
    let branches: [String]
    let base: String
    @ObservedObject var search: BaseSearch
    let pick: (String) -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let shown = matches
        FoundryPopover(label: "Start new branches from") {
            FoundryPopoverHead(title: "Branch from", detail: base.isEmpty ? "HEAD" : base)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ledger.ink3)
                TextField("Find a branch", text: $search.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .onSubmit { if shown.indices.contains(search.picked) { pick(shown[search.picked]) } }
                    .onKeyPress(.downArrow) { move(1, in: shown); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: shown); return .handled }
            }
            .ledgerField()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rule() }

            if shown.isEmpty {
                Text(branches.isEmpty ? "Reading branches…" : "No branch matches.")
                    .font(Ledger.font(13))
                    .foregroundStyle(Ledger.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            } else {
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element) { index, name in
                                row(name, picked: index == search.picked)
                                    .onHover { if $0 { search.picked = index } }
                                    .id(name)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: search.picked) {
                        if shown.indices.contains(search.picked) { scroller.scrollTo(shown[search.picked]) }
                    }
                }
            }
        }
        .onAppear {
            search.query = ""
            search.picked = max(0, branches.firstIndex(of: base) ?? 0)
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: search.query) { search.picked = 0 }
    }

    /// Branches whose name holds the typed text, in the repo's order.
    private var matches: [String] {
        let text = search.query.trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty ? branches : branches.filter { $0.lowercased().contains(text) }
    }

    private func move(_ step: Int, in shown: [String]) {
        guard !shown.isEmpty else { return }
        search.picked = min(max(search.picked + step, 0), shown.count - 1)
    }

    /// A branch as a compact popover row: its name in mono, "base" at the right of the one new
    /// branches start from now; the picked row sunk, with no square (ui-ux/0127).
    private func row(_ name: String, picked: Bool) -> some View {
        Button { pick(name) } label: {
            HStack(spacing: 10) {
                Text(name)
                    .font(Ledger.monoFont(13, picked ? .bold : .regular))
                    .foregroundStyle(Ledger.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if name == base { MonoLabel("Base") }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A popover row has no square; picked, only its fill changes (ui-ux/0127).
            .background(picked ? Ledger.selected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(name == base ? .isSelected : [])
    }
}

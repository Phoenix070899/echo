import HubCore
import SwiftUI

// Foundry's popover (ui-ux/0125): the one look of every floating panel Echo draws, menus, pickers
// and small reports alike. The sheet grey in a 2 pt ink frame casting one hard 6 pt ink block; no
// radius, no blur, no arrow. A mono capital head over a 1 pt rule; menu rows with a 36 pt framed
// icon, a bold title over a one-line note and a key box; the picked row sunk with the accent
// square; a body for reports; a quiet foot line. Echo draws it in the window itself, never in an
// NSPopover, whose frame and arrow cannot be taken off.

// MARK: - The panel and its parts

/// The panel: its parts stacked in the sheet, framed, casting the hard ink block.
struct FoundryPopover<Content: View>: View {
    /// What the panel is, for VoiceOver.
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ledger.paper)
            .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
            // A hard ink block, not a blur: Foundry's raised sheet (ui-ux/0106).
            .background(Rectangle().fill(Ledger.cast).offset(x: PopoverPlacement.cast, y: PopoverPlacement.cast))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}

/// The head: a mono capital label for what the panel is about, a quiet detail at the right, over a
/// 1 pt rule.
struct FoundryPopoverHead: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            MonoLabel(title).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let detail {
                Text(detail).font(Ledger.monoFont(11)).foregroundStyle(Ledger.ink3).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rule() }
    }
}

/// A menu row. With an icon it is Foundry's row: the 36 pt framed icon, the bold title over a
/// one-line note, the key box. Without one it is the compact row of a long menu: the title, the note
/// beside it, the key box. The picked row is the sunk grey with the 6 pt accent square.
struct FoundryPopoverItem: View {
    let title: String
    var note: String?
    var key: String?
    var icon: AnyView?
    var picked = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    icon
                        .foregroundStyle(Ledger.ink)
                        .frame(width: 36, height: 36)
                        .background(Ledger.paper)
                        .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
                    VStack(alignment: .leading, spacing: 0) {
                        titleText
                        if let note { noteText(note) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        titleText
                        if let note { noteText(note) }
                    }
                }
                Spacer(minLength: 8)
                if let key, !key.isEmpty {
                    Text(key)
                        .font(Ledger.monoFont(10, .bold))
                        .foregroundStyle(Ledger.ink3)
                        .frame(width: 40, height: 22)
                        .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, icon == nil ? 7 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(picked && enabled ? Ledger.selected : Color.clear)
            .overlay(alignment: .leading) {
                if picked && enabled { ListMarker(picked: true).padding(.leading, 5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityHint(note ?? "")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var titleText: some View {
        Text(title).font(Ledger.font(15, .bold)).foregroundStyle(Ledger.ink).lineLimit(1)
    }

    private func noteText(_ note: String) -> some View {
        Text(note).font(Ledger.font(13)).foregroundStyle(Ledger.ink3).lineLimit(1).truncationMode(.tail)
    }
}

/// The rule between two groups of rows.
struct FoundryPopoverRule: View {
    var body: some View {
        Rule().padding(.horizontal, 14).padding(.vertical, 4).accessibilityHidden(true)
    }
}

/// A group's quiet mono label inside a menu, such as "Profiles".
struct FoundryPopoverLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        MonoLabel(title)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The body of a report: a ruled table or rows, 14 pt in.
struct FoundryPopoverBody<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One quiet line or link under a 1 pt rule.
struct FoundryPopoverFoot<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(Ledger.font(12))
            .foregroundStyle(Ledger.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rule() }
    }
}

// MARK: - A menu

/// One entry of a Foundry menu.
struct FoundryMenuEntry {
    enum Kind { case item, rule, label }

    var kind = Kind.item
    var title = ""
    var note: String?
    var key: String?
    var icon: AnyView?
    var enabled = true
    var action: () -> Void = {}

    static let rule = FoundryMenuEntry(kind: .rule)

    static func label(_ title: String) -> FoundryMenuEntry { FoundryMenuEntry(kind: .label, title: title) }

    static func item(_ title: String, note: String? = nil, key: String? = nil, icon: AnyView? = nil,
                     enabled: Bool = true, action: @escaping () -> Void) -> FoundryMenuEntry {
        FoundryMenuEntry(title: title, note: note, key: key, icon: icon, enabled: enabled, action: action)
    }
}

/// A menu in Foundry's popover: a head, its entries and a foot. The pointer or ↑ ↓ pick a row,
/// Return runs it, Esc or a click outside closes; a row run closes the menu first. A menu taller
/// than the window scrolls.
struct FoundryMenu: View {
    let label: String
    var head: String?
    var detail: String?
    let entries: [FoundryMenuEntry]
    var foot: AnyView?
    @Environment(\.foundryPopoverClose) private var close
    @StateObject private var pick = MenuPick()
    @FocusState private var focused: Bool

    var body: some View {
        FoundryPopover(label: label) {
            if let head { FoundryPopoverHead(title: head, detail: detail) }
            ViewThatFits(in: .vertical) {
                rows
                ScrollViewReader { scroller in
                    ScrollView { rows }
                        .onChange(of: pick.index) { scroller.scrollTo(pick.index) }
                }
            }
            if let foot { FoundryPopoverFoot { foot } }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { run(pick.index); return .handled }
        .onAppear {
            pick.index = enabledItems.first ?? -1
            DispatchQueue.main.async { focused = true }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                switch entry.kind {
                case .rule:
                    FoundryPopoverRule()
                case .label:
                    FoundryPopoverLabel(entry.title)
                case .item:
                    FoundryPopoverItem(title: entry.title, note: entry.note, key: entry.key, icon: entry.icon,
                                       picked: index == pick.index, enabled: entry.enabled) { run(index) }
                        .onHover { if $0 && entry.enabled { pick.index = index } }
                        .id(index)
                }
            }
        }
    }

    private var enabledItems: [Int] {
        entries.indices.filter { entries[$0].kind == .item && entries[$0].enabled }
    }

    private func move(_ step: Int) {
        let items = enabledItems
        guard !items.isEmpty else { return }
        guard let at = items.firstIndex(of: pick.index) else {
            pick.index = step > 0 ? items[0] : items[items.count - 1]
            return
        }
        pick.index = items[min(max(at + step, 0), items.count - 1)]
    }

    private func run(_ index: Int) {
        guard entries.indices.contains(index), entries[index].kind == .item, entries[index].enabled else { return }
        let action = entries[index].action
        close()
        action()
    }
}

final class MenuPick: ObservableObject {
    @Published var index = 0
}

/// A 1 pt rule across its container.
struct Rule: View {
    var body: some View {
        Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline)
    }
}

// MARK: - Presentation

/// Closes the popover the view is in.
private struct FoundryPopoverCloseKey: EnvironmentKey {
    static var defaultValue: () -> Void { {} }
}

extension EnvironmentValues {
    var foundryPopoverClose: () -> Void {
        get { self[FoundryPopoverCloseKey.self] }
        set { self[FoundryPopoverCloseKey.self] = newValue }
    }
}

/// A popover asked for by a control, carried up to the window's host.
struct FoundryPopoverEntry {
    let anchor: Anchor<CGRect>
    let width: CGFloat
    let trailing: Bool
    let gap: CGFloat
    let content: AnyView
    let close: () -> Void
}

struct FoundryPopoverKey: PreferenceKey {
    static var defaultValue: [FoundryPopoverEntry] { [] }

    static func reduce(value: inout [FoundryPopoverEntry], nextValue: () -> [FoundryPopoverEntry]) {
        value += nextValue()
    }
}

extension View {
    /// Opens `content`, a `FoundryPopover` or `FoundryMenu`, `width` wide under this control while
    /// `isPresented` holds, its leading edge on the control's (or its trailing edge, for a control
    /// at the right of the window). The window's `foundryPopoverHost` draws it.
    func foundryPopover<Content: View>(isPresented: Binding<Bool>, width: CGFloat, trailing: Bool = false,
                                       gap: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) -> some View {
        anchorPreference(key: FoundryPopoverKey.self, value: .bounds) { anchor in
            guard isPresented.wrappedValue else { return [] }
            return [FoundryPopoverEntry(anchor: anchor, width: width, trailing: trailing, gap: gap,
                                        content: AnyView(content()), close: { isPresented.wrappedValue = false })]
        }
    }

    /// Draws the popovers asked for inside this view over it, the last one asked for on top of a
    /// clear layer that closes it on a click; `shown` holds while one is open, so the terminal lets
    /// go of the keyboard.
    func foundryPopoverHost(shown: Binding<Bool>) -> some View {
        overlayPreferenceValue(FoundryPopoverKey.self) { entries in
            GeometryReader { proxy in
                if let entry = entries.last {
                    FoundryPopoverLayer(entry: entry, anchor: proxy[entry.anchor], size: proxy.size, shown: shown)
                }
            }
        }
    }
}

/// The open popover over the window, placed by `PopoverPlacement`.
private struct FoundryPopoverLayer: View {
    let entry: FoundryPopoverEntry
    let anchor: CGRect
    let size: CGSize
    let shown: Binding<Bool>

    var body: some View {
        let place = PopoverPlacement.place(anchor: anchor, width: entry.width, in: size, trailing: entry.trailing, gap: entry.gap)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: entry.close)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                if !place.below { Spacer(minLength: 0) }
                entry.content
                    .environment(\.foundryPopoverClose, entry.close)
                    .onExitCommand(perform: entry.close)
                    .frame(width: entry.width)
                if place.below { Spacer(minLength: 0) }
            }
            .frame(width: entry.width, height: place.height)
            .offset(x: place.x, y: place.y)
        }
        .onAppear { shown.wrappedValue = true }
        .onDisappear { shown.wrappedValue = false }
    }
}

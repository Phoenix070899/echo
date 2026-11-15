import AppKit
import HubCore
import SwiftUI

/// Settings in Foundry (ui-ux/0120): a section is a page with a mono "NN / Name" label, a condensed
/// display title and a 2 pt ink rule, then square label and value rows with 1 pt rules. Nothing here
/// is rounded, so the system's grouped forms, pop-up buttons, switches, steppers, sliders and colour
/// wells are drawn here instead. Every colour is a `Ledger` token, so dark and Custom still work.
enum SettingsLook {
    /// The width of a row's label column, and the gap after it (Foundry's data rows).
    static let labelWidth: CGFloat = 240
    static let labelGap: CGFloat = 40
    /// A section's column, centred in the sheet (ui-ux/0045).
    static let column: CGFloat = 680
    /// Problems and refusals: the failed red, which reads as text where the accent may not.
    static let problem = Ledger.fail
    /// The accent's deep shade, for a second model family in the Team's bar.
    static let accentDeep = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.82, green: 0.47, blue: 0.27, alpha: 1)
            : NSColor(srgbRed: 0x8F / 255, green: 0x45 / 255, blue: 0x19 / 255, alpha: 1)
    })

    /// "06": a section's place in the list.
    static func number(_ section: SettingsSection) -> String {
        let at = (SettingsSection.allCases.firstIndex(of: section) ?? 0) + 1
        return at < 10 ? "0\(at)" : "\(at)"
    }
}

/// A mono capital label at Foundry's size: 12 pt bold, tracked a tenth of an em.
struct SettingsLabel: View {
    let text: String
    var size: CGFloat = 12
    var color: Color = Ledger.ink3

    init(_ text: String, size: CGFloat = 12, color: Color = Ledger.ink3) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Ledger.monoFont(size, .bold))
            .tracking(size * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A section's head: a 2 pt ink rule, the mono "NN / Name" label, and the title in condensed capitals.
struct SettingsHead: View {
    let label: String
    let title: String
    var size: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsLabel(label)
            Text(title)
                .font(Ledger.display(size))
                .textCase(.uppercase)
                .foregroundStyle(Ledger.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
    }
}

/// One section's page: its head and groups in a column at most 680 pt wide, centred in the sheet,
/// scrolling when taller than the window.
struct SettingsSheetPage<Content: View>: View {
    let section: SettingsSection
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                SettingsHead(label: "\(SettingsLook.number(section)) / \(section.title)", title: title ?? section.title)
                content()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 56)
            .frame(maxWidth: SettingsLook.column)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// A group of rows under a 2 pt ink rule, with its name above the rule when it has one.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SettingsLabel(title, color: Ledger.ink)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
            }
            Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong)
            content()
        }
        .accessibilityElement(children: .contain)
    }
}

/// A label and its value, Foundry's data row: the label bold in a 240 pt column, the value beside it,
/// a 1 pt rule under them. Without a label the value takes the whole row.
struct SettingsRow<Value: View>: View {
    var label: String?
    @ViewBuilder var value: () -> Value

    init(_ label: String? = nil, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLook.labelGap) {
            if let label {
                Text(label)
                    .font(Ledger.font(17, .bold))
                    .foregroundStyle(Ledger.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: SettingsLook.labelWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 10) {
                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
    }
}

/// A grey line under a control: what it does, or why. A problem is in the failed red.
struct SettingsNote: View {
    let text: String
    var problem = false
    var size: CGFloat = 14

    init(_ text: String, problem: Bool = false, size: CGFloat = 14) {
        self.text = text
        self.problem = problem
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(Ledger.font(size))
            .lineSpacing(size * 0.35)
            .foregroundStyle(problem ? SettingsLook.problem : Ledger.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Buttons

/// Settings' buttons, Foundry's at their full size: 34 pt, mono capitals tracked .06 em. The primary
/// is ink casting a hard 3 pt accent block (ui-ux/0106); the rest are a 2 pt ink frame on no fill.
struct SettingsButtonStyle: ButtonStyle {
    var primary = false
    var height: CGFloat = 34
    /// Stretch to the width offered, like the list's New Team.
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, primary: primary, height: height, fill: fill)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let height: CGFloat
        let fill: Bool
        @Environment(\.isEnabled) private var isEnabled
        @StateObject private var hover = Flag()

        var body: some View {
            // Hovered, the primary moves halfway onto its block, the secondary takes the hover fill (ui-ux/0131).
            let hovered = hover.on && isEnabled
            let pressed: CGFloat = !primary ? 0 : configuration.isPressed ? 3 : hovered ? 1.5 : 0
            configuration.label
                .font(Ledger.monoFont(11, .bold))
                .tracking(0.66)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize(horizontal: !fill, vertical: false)
                .padding(.horizontal, primary ? 18 : 12)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
                .foregroundStyle(primary ? Ledger.onPrimary : Ledger.ink)
                .background(primary ? Ledger.primary : configuration.isPressed ? Ledger.fill : hovered ? Ledger.wash : Color.clear)
                .overlay(Rectangle().strokeBorder(primary ? Color.clear : Ledger.ink, lineWidth: Ledger.ruleStrong))
                .offset(x: pressed, y: pressed)
                .background {
                    if primary && isEnabled { Rectangle().fill(Ledger.accent).offset(x: 3, y: 3) }
                }
                .padding(.trailing, primary ? 3 : 0)
                .padding(.bottom, primary ? 3 : 0)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
    static var settingsPrimary: SettingsButtonStyle { SettingsButtonStyle(primary: true) }
}

// MARK: Menus

/// One entry of a menu drawn by AppKit under a square control.
struct MenuEntry {
    var title = ""
    var checked = false
    var action: () -> Void

    static func item(_ title: String, checked: Bool = false, action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, checked: checked, action: action)
    }
}

/// Where a menu opens: the AppKit view under a SwiftUI control, kept by an anchor in its background.
@MainActor
final class MenuAnchor: ObservableObject {
    weak var view: NSView?

    /// Opens `entries` under the control, at least as wide as it.
    func open(_ entries: [MenuEntry]) {
        guard let view else { return }
        let menu = Self.menu(entries)
        menu.minimumWidth = view.bounds.width
        let y = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    private static func menu(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = Ledger.nsFont(13)
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(MenuTarget.fire), keyEquivalent: "")
            item.state = entry.checked ? .on : .off
            let target = MenuTarget(entry.action)
            item.target = target
            // The item keeps its target alive while the menu is up.
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
    }
}

private final class MenuTarget: NSObject {
    let run: () -> Void

    init(_ run: @escaping () -> Void) { self.run = run }

    @objc func fire() { run() }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

extension View {
    /// Marks the view as where `anchor`'s menus open.
    func menuAnchor(_ anchor: MenuAnchor) -> some View {
        background(AnchorView(anchor: anchor))
    }
}

/// A button whose click opens an AppKit menu under it, so its label can be drawn square in any style.
struct MenuButton<Label: View>: View {
    let entries: () -> [MenuEntry]
    @ViewBuilder var label: () -> Label
    @StateObject private var anchor = MenuAnchor()

    var body: some View {
        Button { anchor.open(entries()) } label: { label() }
            .menuAnchor(anchor)
    }
}

// MARK: Fields

/// How strong a field's frame is: a page's control is framed in 2 pt ink and 40 pt tall; an
/// inspector's in 1 pt muted ink and 38 pt tall.
enum FieldWeight {
    case page, inspector

    var height: CGFloat { self == .page ? 40 : 38 }
    var frame: CGFloat { self == .page ? Ledger.ruleStrong : Ledger.hairline }
    var frameColor: Color { self == .page ? Ledger.ink : Ledger.ink3 }
    var size: CGFloat { self == .page ? 15 : 14 }
}

/// A choice from a list, square: the picked title and a chevron in a framed field; the list is an
/// AppKit menu with the pick ticked.
struct SquarePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var weight = FieldWeight.page
    var label = ""
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = Flag()

    var body: some View {
        MenuButton(entries: {
            options.map { option in
                .item(option.title, checked: option.value == selection) { selection = option.value }
            }
        }) {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(Ledger.font(weight.size))
                    .foregroundStyle(Ledger.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ledger.ink)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: weight.height)
            .background(hover.on && isEnabled ? Ledger.wash : Ledger.paper)
            .overlay(Rectangle().strokeBorder(weight.frameColor, lineWidth: weight.frame))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
    }
}

extension View {
    /// A square text field (pair with `.textFieldStyle(.plain)`): the sheet's grey in a frame.
    func squareField(_ weight: FieldWeight = .page, mono: Bool = false) -> some View {
        modifier(SquareField(weight: weight, mono: mono))
    }
}

private struct SquareField: ViewModifier {
    let weight: FieldWeight
    let mono: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? Ledger.monoFont(weight.size - 1) : Ledger.font(weight.size))
            .foregroundStyle(Ledger.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: weight.height, alignment: .leading)
            .background(Ledger.paper)
            .overlay(Rectangle().strokeBorder(weight.frameColor, lineWidth: weight.frame))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A field in an inspector: its mono capital label over the control.
struct InspectorField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLabel(label, size: 11)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A part of an inspector under a 1 pt rule, its name in ink capitals.
struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsLabel(title, size: 11, color: Ledger.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Toggles, steppers, sliders, segments, colours

/// A square checkbox: a 2 pt ink frame, solid ink with a tick when on; the label beside it.
struct SquareToggleStyle: ToggleStyle {
    var size: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, size: size)
    }

    private struct Styled: View {
        let configuration: ToggleStyleConfiguration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @StateObject private var hover = Flag()

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    box
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + size * 0.35 }
                    configuration.label
                        .font(Ledger.font(size))
                        .foregroundStyle(Ledger.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover.on = $0 }
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
            .accessibilityValue(configuration.isOn ? "on" : "off")
        }

        private var box: some View {
            Rectangle()
                .fill(configuration.isOn ? Ledger.ink : hover.on && isEnabled ? Ledger.wash : Ledger.paper)
                .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Ledger.paper)
                    }
                }
                .frame(width: 18, height: 18)
        }
    }
}

extension ToggleStyle where Self == SquareToggleStyle {
    static var square: SquareToggleStyle { SquareToggleStyle() }
}

/// A number with square minus and plus buttons after it.
struct SquareStepper: View {
    let text: String
    let minus: (() -> Void)?
    let plus: (() -> Void)?
    var label = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(Ledger.font(15))
                .foregroundStyle(Ledger.ink)
                .monospacedDigit()
            Spacer(minLength: 0)
            HStack(spacing: -Ledger.ruleStrong) {
                step("minus", "Less", minus)
                step("plus", "More", plus)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func step(_ symbol: String, _ name: String, _ action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(SettingsButtonStyle(height: 34))
        .disabled(action == nil)
        .accessibilityLabel(name)
    }
}

/// A slider drawn square: a 2 pt ink track, filled ink up to a square handle.
struct SquareSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var label = ""
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - 12)
            let at = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * width
            ZStack(alignment: .leading) {
                Rectangle().fill(Ledger.rule).frame(height: Ledger.ruleStrong)
                Rectangle().fill(Ledger.ink).frame(width: at + 6, height: Ledger.ruleStrong)
                Rectangle().fill(Ledger.ink).frame(width: 12, height: 20).offset(x: at)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let share = min(max((drag.location.x - 6) / width, 0), 1)
                value = range.lowerBound + Double(share) * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 24)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
}

/// A segmented choice across the width it is given: Foundry's sunk track, 3 pt inside, the pick on
/// the sheet's grey in a 2 pt ink frame. `inherited` is framed dashed when nothing is picked, for a
/// value that comes from the level below.
struct FillSegmented: View {
    let options: [String]
    let picked: String?
    var inherited: String?
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == picked
                let shown = picked == nil && option == inherited
                Button { pick(option) } label: {
                    Text(option)
                        .font(Ledger.monoFont(11, .bold))
                        .tracking(0.66)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(on || shown ? Ledger.ink : Ledger.ink3)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(on ? Ledger.paper : .clear)
                        .overlay {
                            if on {
                                Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong)
                            } else if shown {
                                Rectangle().strokeBorder(Ledger.ink3, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverFill(active: !on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Ledger.bubble)
    }
}

/// A colour, square: a swatch in an ink frame with its hex beside it; clicking opens the colour panel.
struct SquareColorWell: View {
    @Binding var selection: Color
    var label = ""

    var body: some View {
        Button { ColorPanelTarget.shared.open(selection) { selection = $0 } } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(selection)
                    .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
                    .frame(width: 48, height: 28)
                Text(hex)
                    .font(Ledger.monoFont(12))
                    .foregroundStyle(Ledger.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFill()
        .accessibilityLabel(label)
        .accessibilityValue(hex)
    }

    private var hex: String {
        guard let rgb = NSColor(selection).usingColorSpace(.sRGB) else { return "" }
        return TerminalTheme.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).uppercased()
    }
}

/// The shared colour panel, pointed at the well clicked last.
@MainActor
private final class ColorPanelTarget: NSObject {
    static let shared = ColorPanelTarget()
    private var set: ((Color) -> Void)?

    func open(_ color: Color, set: @escaping (Color) -> Void) {
        self.set = set
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.color = NSColor(color)
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        set?(Color(nsColor: panel.color))
    }
}

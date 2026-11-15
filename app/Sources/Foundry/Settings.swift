import AppKit
import HubCore
import SwiftUI

/// Settings in Foundry (ui-ux/0120): a section is a page with a mono "NN / Name" label, a condensed
/// display title and a 2 pt ink rule, then square label and value rows with 1 pt rules. Nothing here
/// is rounded, so the system's grouped forms, pop-up buttons, switches, steppers, sliders and colour
/// wells are drawn here instead. Every colour is a `Ledger` token, so dark and Custom still work.
public enum SettingsLook {
    /// The width of a row's label column, and the gap after it (Foundry's data rows).
    public static let labelWidth: CGFloat = 240
    public static let labelGap: CGFloat = 40
    /// A section's column, centred in the sheet (ui-ux/0045).
    public static let column: CGFloat = 680
    /// Problems and refusals: the failed red, which reads as text where the accent may not.
    public static let problem = Ledger.fail
    /// The accent's deep shade, for a second model family in the Team's bar.
    public static let accentDeep = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.82, green: 0.47, blue: 0.27, alpha: 1)
            : NSColor(srgbRed: 0x8F / 255, green: 0x45 / 255, blue: 0x19 / 255, alpha: 1)
    })
}

/// A mono capital label at Foundry's size: 12 pt bold, tracked a tenth of an em.
public struct SettingsLabel: View {
    public let text: String
    public var size: CGFloat = 12
    public var color: Color = Ledger.ink3

    public init(_ text: String, size: CGFloat = 12, color: Color = Ledger.ink3) {
        self.text = text
        self.size = size
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(Ledger.monoFont(size, .bold))
            .tracking(size * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A section's head: a 2 pt ink rule, the mono "NN / Name" label, and the title in condensed capitals.
public struct SettingsHead: View {
    public let label: String
    public let title: String
    public var size: CGFloat = 52

    public init(label: String, title: String, size: CGFloat = 52) {
        self.label = label
        self.title = title
        self.size = size
    }

    public var body: some View {
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

/// A group of rows under a 2 pt ink rule, with its name above the rule when it has one.
public struct SettingsGroup<Content: View>: View {
    public var title: String?
    @ViewBuilder public var content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
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
public struct SettingsRow<Value: View>: View {
    public var label: String?
    @ViewBuilder public var value: () -> Value

    public init(_ label: String? = nil, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    public var body: some View {
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
public struct SettingsNote: View {
    public let text: String
    public var problem = false
    public var size: CGFloat = 14

    public init(_ text: String, problem: Bool = false, size: CGFloat = 14) {
        self.text = text
        self.problem = problem
        self.size = size
    }

    public var body: some View {
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
/// A destructive button takes the failed red where the others take ink (ui-ux/0140).
public struct SettingsButtonStyle: ButtonStyle {
    public var primary = false
    public var height: CGFloat = 34
    /// Stretch to the width offered, like the list's New Team.
    public var fill = false
    public var destructive = false

    public init(primary: Bool = false, height: CGFloat = 34, fill: Bool = false, destructive: Bool = false) {
        self.primary = primary
        self.height = height
        self.fill = fill
        self.destructive = destructive
    }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, primary: primary, height: height, fill: fill, destructive: destructive)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let height: CGFloat
        let fill: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @StateObject private var hover = Flag()

        var body: some View {
            let ink = destructive ? Ledger.fail : Ledger.ink
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
                .foregroundStyle(primary ? Ledger.onPrimary : ink)
                .background(primary ? (destructive ? Ledger.fail : Ledger.primary)
                    : configuration.isPressed ? Ledger.fill : hovered ? Ledger.wash : Color.clear)
                .overlay(Rectangle().strokeBorder(primary ? Color.clear : ink, lineWidth: Ledger.ruleStrong))
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
    public static var settings: SettingsButtonStyle { SettingsButtonStyle() }
    public static var settingsPrimary: SettingsButtonStyle { SettingsButtonStyle(primary: true) }
}

// MARK: Menus

/// A button whose click opens a Foundry menu under it (ui-ux/0125), at least as wide as the button.
public struct MenuButton<Label: View>: View {
    public let label: String
    public let entries: () -> [FoundryMenuEntry]
    @ViewBuilder public var content: () -> Label
    @StateObject private var open = Flag()
    @StateObject private var width = Measure()

    public init(label: String, entries: @escaping () -> [FoundryMenuEntry], @ViewBuilder content: @escaping () -> Label) {
        self.label = label
        self.entries = entries
        self.content = content
    }

    public var body: some View {
        Button { open.on.toggle() } label: { content() }
            .background(GeometryReader { proxy in
                Color.clear.onAppear { width.value = proxy.size.width }
                    .onChange(of: proxy.size.width) { width.value = proxy.size.width }
            })
            .foundryPopover(isPresented: $open.on, width: max(width.value, 220), gap: 4) {
                FoundryMenu(label: label, entries: entries())
            }
    }
}

/// A width read from layout, held outside the view (no `@State` here).
final class Measure: ObservableObject {
    @Published var value: CGFloat = 0
}

// MARK: Fields

/// How strong a field's frame is: a page's control is framed in 2 pt ink and 40 pt tall; an
/// inspector's in 1 pt muted ink and 38 pt tall.
public enum FieldWeight {
    case page, inspector

    public var height: CGFloat { self == .page ? 40 : 38 }
    public var frame: CGFloat { self == .page ? Ledger.ruleStrong : Ledger.hairline }
    public var frameColor: Color { self == .page ? Ledger.ink : Ledger.ink3 }
    public var size: CGFloat { self == .page ? 15 : 14 }
}

/// A choice from a list, square: the picked title and a chevron in a framed field; the list is a
/// Foundry menu with the pick ticked.
public struct SquarePicker<Value: Hashable>: View {
    @Binding public var selection: Value
    public let options: [(value: Value, title: String)]
    public var weight = FieldWeight.page
    public var label = ""
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = Flag()

    public init(selection: Binding<Value>, options: [(value: Value, title: String)], weight: FieldWeight = .page, label: String = "") {
        self._selection = selection
        self.options = options
        self.weight = weight
        self.label = label
    }

    public var body: some View {
        MenuButton(label: label, entries: {
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
    public func squareField(_ weight: FieldWeight = .page, mono: Bool = false) -> some View {
        modifier(SquareField(weight: weight, mono: mono))
    }
}

private struct SquareField: ViewModifier {
    public let weight: FieldWeight
    public let mono: Bool
    @Environment(\.isEnabled) private var isEnabled

    public func body(content: Content) -> some View {
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
public struct InspectorField<Content: View>: View {
    public let label: String
    @ViewBuilder public var content: () -> Content

    public init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLabel(label, size: 11)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A part of an inspector under a 1 pt rule, its name in ink capitals.
public struct InspectorGroup<Content: View>: View {
    public let title: String
    @ViewBuilder public var content: () -> Content

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
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

/// A square checkbox (ui-ux/0139): a 2 pt ink frame, solid ink with a tick when on; the label beside
/// it. Echo's on and off switch, in place of the system's toggle.
public struct Checkbox: View {
    public let title: String
    @Binding public var isOn: Bool
    public var size: CGFloat = 15
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = Flag()

    public init(_ title: String, isOn: Binding<Bool>, size: CGFloat = 15) {
        self.title = title
        self._isOn = isOn
        self.size = size
    }

    public var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                box
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + size * 0.35 }
                Text(title)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isOn ? "on" : "off")
    }

    private var box: some View {
        Rectangle()
            .fill(isOn ? Ledger.ink : hover.on && isEnabled ? Ledger.wash : Ledger.paper)
            .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Ledger.paper)
                }
            }
            .frame(width: 18, height: 18)
    }
}

/// A number with square minus and plus buttons after it.
public struct SquareStepper: View {
    public let text: String
    public let minus: (() -> Void)?
    public let plus: (() -> Void)?
    public var label = ""

    public init(text: String, minus: (() -> Void)? = nil, plus: (() -> Void)? = nil, label: String = "") {
        self.text = text
        self.minus = minus
        self.plus = plus
        self.label = label
    }

    public var body: some View {
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
public struct SquareSlider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public var label = ""
    @Environment(\.isEnabled) private var isEnabled

    public init(value: Binding<Double>, range: ClosedRange<Double>, label: String = "") {
        self._value = value
        self.range = range
        self.label = label
    }

    public var body: some View {
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
public struct FillSegmented: View {
    public let options: [String]
    public let picked: String?
    public var inherited: String?
    public let pick: (String) -> Void

    public init(options: [String], picked: String? = nil, inherited: String? = nil, pick: @escaping (String) -> Void) {
        self.options = options
        self.picked = picked
        self.inherited = inherited
        self.pick = pick
    }

    public var body: some View {
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
public struct SquareColorWell: View {
    @Binding public var selection: Color
    public var label = ""

    public init(selection: Binding<Color>, label: String = "") {
        self._selection = selection
        self.label = label
    }

    public var body: some View {
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
    public static let shared = ColorPanelTarget()
    private var set: ((Color) -> Void)?

    public func open(_ color: Color, set: @escaping (Color) -> Void) {
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

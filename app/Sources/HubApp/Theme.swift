import AppKit
import HubCore
import SwiftUI

/// The Ledger look in Foundry, the human's design system (ui-ux/0104): a pale concrete desk, a
/// lighter sheet for panels, near-black ink, 1 pt rules, square corners, and a muted safety orange
/// that marks things but is never text. Dark mode keeps the values it had before Foundry.
enum Ledger {
    /// The window, and the sidebar that sits flat on it.
    static let desk = dynamic(0xE6E4DF, 0x1F1E1D) { $0.background }
    /// The chat canvas and every panel beside it.
    static let paper = dynamic(0xEFEEEA, 0x262624) { $0.surface }
    static let ink = dynamic(0x2B2B29, 0xFAF9F5) { $0.text }
    static let ink2 = dynamic(0x45433F, 0xC2C0B6) { CustomLook.mix($0.text, $0.surface, 0.3) }
    /// The quietest text; still 4.5:1 or better on every fill it sits on.
    static let ink3 = dynamic(0x5E5B55, 0x9C9A92) { CustomLook.mix($0.text, $0.surface, 0.4) }
    /// Foundry's line: dividers between rows and around sheets.
    static let rule = dynamic(0xC2BEB5, 0x3F3E3B) { CustomLook.mix($0.surface, $0.text, 0.14) }
    /// A hovered row, and a code block's fill.
    static let wash = dynamic(0xDFDCD6, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.05) }
    /// The row picked in the sidebar; `accent` marks its leading edge.
    static let selected = dynamic(0xD8D5CE, 0x3A3936) { CustomLook.mix($0.surface, $0.accent, 0.12) }
    /// The human's message bubble: the sunk grey, darker than the canvas in both modes.
    static let bubble = dynamic(0xD8D5CE, 0x141413) { CustomLook.mix($0.surface, $0.text, 0.07) }
    // Areas are told apart by fills and rules.
    static let strip = dynamic(0xE6E4DF, 0x1F1E1D) { CustomLook.mix($0.background, $0.surface, 0.4) }
    static let pill = dynamic(0xEFEEEA, 0x30302E) { CustomLook.mix($0.surface, $0.dark ? $0.text : "#ffffff", 0.1) }
    /// A title row's band: the desk, so a tab strip reads as a strip above its sheet.
    static let band = dynamic(0xE6E4DF, 0x262624) { $0.surface }
    /// A Needs you item's card.
    static let needCard = dynamic(0xF2DDCD, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.16) }
    /// Chips and other quiet fills.
    static let fill = dynamic(0xD8D5CE, 0x3A3936) { CustomLook.mix($0.surface, $0.text, 0.09) }
    /// The primary button, and the text on it: Foundry's ink, its accent shown as a hard offset.
    static let primary = dynamic(0x2B2B29, 0xD97757) { $0.text }
    static let onPrimary = dynamic(0xEFEEEA, 0x141413) { $0.surface }
    /// The message box and text fields: the sheet's grey inside an ink or grey rule.
    static let field = dynamic(0xEFEEEA, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.06) }
    /// The picked one of a few choices, like a mode card.
    static let chosen = dynamic(0xEBC9B0, 0x45402F) { CustomLook.mix($0.surface, $0.accent, 0.22) }
    /// Foundry's muted safety orange: marks, meters, the picked row's edge, the button's offset. Never
    /// text in light mode (3.1:1 on the sheet).
    static let accent = dynamic(0xC8642E, 0xD9773F) { $0.accent }
    /// The highlighter. Text on it is always dark ink, in both modes.
    static let marker = dynamic(0xEBC9B0, 0xD4A27F) { $0.highlighter }
    static let markerInk = rgb(0x2B2B29)
    static let markerWash = dynamic(0xF2DDCD, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.14) }
    static let run = dynamic(0x3F6A92, 0x6A9BCC) { $0.accent }
    static let done = dynamic(0x5B6E42, 0x9BB07C)
    static let fail = dynamic(0xA33A2A, 0xF2877B)
    /// A file changed but not committed, in the Files column; amber, apart from added green.
    static let changed = dynamic(0x8A5E12, 0xD4A27F)
    /// Lines an agent just changed in an open preview, for a moment.
    static let justChanged = dynamic(0xF0DFC7, 0x3D3320) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.18 : 0.3) }
    static let okWash = dynamic(0xE3E8D6, 0x2B3123)
    static let okInk = dynamic(0x3F5230, 0xBCD0A0)
    static let failWash = dynamic(0xF1DCD5, 0x4A2420)
    static let failInk = dynamic(0x8C1D14, 0xF5B3AA)

    /// Foundry is square: every radius is 0. The names stay so each view keeps saying which kind of
    /// shape it is.
    static let radiusInner: CGFloat = 0
    static let radiusElement: CGFloat = 0
    static let radiusCard: CGFloat = 0
    static let radiusContainer: CGFloat = 0
    /// Foundry's rule is a full point; section and control frames are `ruleStrong`.
    static let hairline: CGFloat = 1
    static let ruleStrong: CGFloat = 2

    /// The faces Echo bundles (ui-ux/0104): Archivo for the interface, JetBrains Mono for code,
    /// labels and readouts. A face that is missing falls back to the system's.
    static let sansFamily = "Archivo"
    static let monoFamily = "JetBrains Mono"

    static let mono = monoFont(12)

    /// The interface's sans: Archivo at the weight asked for.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(sansFamily, fixedSize: size).weight(weight)
    }

    /// Code, paths and readouts: JetBrains Mono.
    static func monoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, fixedSize: size).weight(weight)
    }

    /// Titles: Archivo at its heaviest, 75 % wide, set in capitals by the view.
    static func display(_ size: CGFloat) -> Font {
        Font(variable(sansFamily, size, weight: 800, width: 75) ?? .systemFont(ofSize: size, weight: .heavy))
    }

    /// `font`'s face as an NSFont, for text AppKit draws.
    static func nsFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> NSFont {
        variable(sansFamily, size, weight: axisWeight(weight))
            ?? .systemFont(ofSize: size, weight: weight == .medium ? .medium : weight == .semibold ? .semibold : weight == .bold ? .bold : .regular)
    }

    /// `monoFont`'s face as an NSFont.
    static func nsMono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let value: CGFloat = weight == .semibold ? 600 : weight == .bold ? 700 : weight == .medium ? 500 : 400
        return variable(monoFamily, size, weight: value) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func axisWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    /// A variable face at a weight (and width), or nil when the face is not registered.
    private static func variable(_ family: String, _ size: CGFloat, weight: CGFloat, width: CGFloat? = nil) -> NSFont? {
        guard let base = NSFont(name: family, size: size) else { return nil }
        var axes: [NSNumber: CGFloat] = [NSNumber(value: 0x7767_6874): weight] // 'wght'
        if let width { axes[NSNumber(value: 0x7764_7468)] = width } // 'wdth'
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Registers the bundled faces for this process; a build without them keeps the system's.
    static func registerFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(nsColor: nsColor(hex))
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The human's colours while Window's Appearance is Custom; nil for Echo's own.
    nonisolated(unsafe) private(set) static var custom: CustomLook?

    /// Sets the whole app's appearance (nil follows macOS) and Custom's colours; true when the
    /// colours changed, so views must resolve them again (`LookRefresh`).
    @MainActor @discardableResult
    static func apply(custom: CustomLook?, appearance name: NSAppearance.Name?) -> Bool {
        let recolour = custom != self.custom
        self.custom = custom
        NSApp?.appearance = name.flatMap { NSAppearance(named: $0) }
        return recolour
    }

    /// A token with its light and dark value, and how Custom makes it from the picked colours; a
    /// token without one takes its value for Custom's base mode.
    private static func dynamic(_ light: Int, _ dark: Int, custom: ((CustomLook) -> String)? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if let look = Ledger.custom {
                if let custom, let c = TerminalTheme.rgb(custom(look)) {
                    return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
                }
                return nsColor(look.dark ? dark : light)
            }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? nsColor(dark) : nsColor(light)
        })
    }
}

extension WorkerRow {
    /// Running blue, needing the human amber, done green, ended grey, anything that settled badly red.
    var markColor: Color {
        if isActive { return state == .needsYou ? Ledger.changed : Ledger.run }
        if phase == "ended" { return Ledger.ink3 }
        return isTrouble ? Ledger.fail : Ledger.done
    }

    /// "Running", "Waiting", "Needs you", "Done", "Ended", "Blocked", "Exited", "Lost".
    var phaseLabel: String {
        if isActive {
            switch state {
            case .waiting: return "Waiting"
            case .needsYou: return "Needs you"
            default: return "Running"
            }
        }
        return phase.prefix(1).uppercased() + phase.dropFirst()
    }
}

extension SessionInfo {
    /// The repo path with the home folder as `~`.
    var shortPath: String {
        let home = NSHomeDirectory()
        return repo.hasPrefix(home) ? "~" + repo.dropFirst(home.count) : repo
    }
}

/// A Worker's state as a small square.
struct StateMark: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// Something in progress: an arc turning once a second (slower for work only waiting in the
/// background), in the colour of what it stands for. Under Reduce Motion it stands still.
/// Core Animation turns it, off the main thread: a SwiftUI animation laid the whole window out
/// again on every frame for every spinner on screen (bugs/0062).
struct Spinner: View {
    var color: Color = Ledger.ink3
    var size: CGFloat = 10
    var period: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpinnerArc(color: NSColor(color), lineWidth: max(1.5, size / 6), period: reduceMotion ? nil : period)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SpinnerArc: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat
    /// Seconds a turn takes; nil stands still.
    let period: Double?

    func makeNSView(context: Context) -> SpinnerArcView { SpinnerArcView() }

    func updateNSView(_ view: SpinnerArcView, context: Context) {
        view.update(color: color, lineWidth: lineWidth, period: period)
    }
}

final class SpinnerArcView: NSView {
    private let arc = CAShapeLayer()
    private var color = NSColor.clear
    private var period: Double?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError("SpinnerArcView is built in code") }

    func update(color: NSColor, lineWidth: CGFloat, period: Double?) {
        self.color = color
        arc.lineWidth = lineWidth
        if period != self.period {
            self.period = period
            spin()
        }
        resolveColor()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        let inset = arc.lineWidth / 2
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let path = CGMutablePath()
        // From 3 o'clock, clockwise on screen (the layer's y runs up), as SwiftUI's trimmed circle did.
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: 0, endAngle: -0.7 * 2 * .pi, clockwise: true)
        arc.path = path
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColor()
    }

    /// Leaving a window drops a layer's animations; coming back starts the turn again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spin()
    }

    /// A spinner sits inside rows and buttons; clicks go to them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func resolveColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance { arc.strokeColor = color.cgColor }
        CATransaction.commit()
    }

    private func spin() {
        arc.removeAnimation(forKey: "turn")
        guard let period, window != nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        // Clockwise on screen: the layer's y runs up.
        turn.toValue = -2 * Double.pi
        turn.duration = period
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        arc.add(turn, forKey: "turn")
    }
}

/// A Worker's state mark: a spinner while it works (slower while it only waits on background
/// work), the still square once it settles or needs the human.
struct WorkerMark: View {
    let worker: WorkerRow

    var body: some View {
        if worker.isActive && worker.state != .needsYou {
            Spinner(color: worker.markColor, size: 10, period: worker.state == .waiting ? 2.4 : 1)
        } else {
            StateMark(color: worker.markColor)
        }
    }
}

/// The target: something waits on the human. A square on the accent's soft fill, with a solid
/// square at its centre (ui-ux/0108).
struct NeedsRing: View {
    var size: CGFloat = 14

    var body: some View {
        Rectangle().fill(Ledger.marker)
            .overlay(Rectangle().strokeBorder(Ledger.accent, lineWidth: max(1.5, size / 8)))
            .overlay(Rectangle().fill(Ledger.accent).frame(width: size * 0.32, height: size * 0.32))
            .frame(width: size, height: size)
            .accessibilityLabel("Needs you")
    }
}

/// A Worker's mark at the right of its sidebar row (ui-ux/0092, squared by ui-ux/0108): a turning
/// ring while it works (slower while it only waits on background work), the square target when it
/// needs the human, a solid green square with a tick when it is done, a plain grey tick when it ended
/// at its input box, a solid red square with a cross when it went wrong.
struct WorkerGlyph: View {
    let worker: WorkerRow
    private let size: CGFloat = 14

    var body: some View {
        Group {
            if worker.isActive && worker.state == .needsYou {
                NeedsRing(size: size)
            } else if worker.isActive {
                Spinner(color: worker.markColor, size: size - 1, period: worker.state == .waiting ? 2.4 : 1)
            } else if worker.phase == "ended" {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ledger.ink3)
            } else if worker.isTrouble {
                SquareGlyph(symbol: "xmark", fill: Ledger.fail, size: size)
            } else {
                SquareGlyph(symbol: "checkmark", fill: Ledger.done, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(worker.phaseLabel)
    }
}

/// A solid square with a symbol cut out of it in the sheet's colour.
struct SquareGlyph: View {
    let symbol: String
    let fill: Color
    var size: CGFloat = 14

    var body: some View {
        Rectangle().fill(fill)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.55, weight: .heavy)).foregroundStyle(Ledger.paper))
            .frame(width: size, height: size)
    }
}

/// A small mono label in capitals: section names, tabs, readouts.
struct MonoLabel: View {
    let text: String
    var color: Color = Ledger.ink3

    init(_ text: String, color: Color = Ledger.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Ledger.monoFont(10.5, .bold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A line saying something is being read or started, with a spinner before it.
struct Pending: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 6) {
            Spinner(size: 10)
            Text(text)
        }
    }
}

/// Text under the highlighter: reserved for things waiting on the human.
struct Marked: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(Ledger.markerInk)
            .padding(.horizontal, 3)
            .background(Ledger.marker)
    }
}

/// The ledger's buttons (ui-ux/0106): the primary is solid ink casting a hard accent offset that
/// presses flat; the rest are an ink outline. Mono capitals, square, 28 pt tall or 32 pt when large.
struct LedgerButtonStyle: ButtonStyle {
    var primary = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, primary: primary, large: large)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let large: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed: CGFloat = primary && configuration.isPressed ? 3 : 0
            configuration.label
                .font(Ledger.monoFont(11, .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .lineLimit(1)
                // A label never truncates: capitals in mono run wider than the sans they replaced.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, large ? 14 : 10)
                .frame(minHeight: large ? 32 : 28)
                .foregroundStyle(primary ? Ledger.onPrimary : Ledger.ink)
                .background(primary ? Ledger.primary : Color.clear)
                .overlay(Rectangle().strokeBorder(primary ? Color.clear : Ledger.ink, lineWidth: 1.5))
                .offset(x: pressed, y: pressed)
                // The offset is a solid block behind the button, not a blurred shadow (ui-ux/0106);
                // pressing moves the button onto it.
                .background {
                    if primary && isEnabled { Rectangle().fill(Ledger.accent).offset(x: 3, y: 3) }
                }
                .padding(.trailing, primary ? 3 : 0)
                .padding(.bottom, primary ? 3 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == LedgerButtonStyle {
    static var ledger: LedgerButtonStyle { LedgerButtonStyle() }
    static var ledgerPrimary: LedgerButtonStyle { LedgerButtonStyle(primary: true) }
    static var ledgerLarge: LedgerButtonStyle { LedgerButtonStyle(primary: true, large: true) }
}

/// A segmented choice (ui-ux/0107): a sunk square track, the picked choice on the sheet's grey
/// inside a 1.5 pt ink frame, mono capitals. Stands in for the system's segmented picker, whose
/// accent-blue thumb belongs to no other control here.
struct LedgerSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    SegmentLabel(title: option.title, on: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Ledger.bubble)
        .fixedSize()
    }
}

/// One choice of a segmented control, picked or not.
struct SegmentLabel: View {
    let title: String
    let on: Bool

    var body: some View {
        Text(title)
            .font(Ledger.monoFont(10.5, .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(on ? Ledger.ink : Ledger.ink3)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(on ? Ledger.field : .clear)
            .overlay(Rectangle().strokeBorder(on ? Ledger.ink : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
    }
}

/// A text link, for quiet actions like Show all: ink, underlined in the accent.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ledger.font(13, .semibold))
            .foregroundStyle(Ledger.ink)
            .underline(true, color: Ledger.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var ledgerLink: LinkButtonStyle { LinkButtonStyle() }
}

extension View {
    /// A sheet of paper on the desk, set apart by its fill alone, on the container radius.
    func ledgerSheet() -> some View {
        background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous)
                .strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
    }

    /// Lays the view out in exactly the room it is offered and cuts what does not fit. Without it a
    /// view whose content cannot shrink (a header, a grid, a terminal) sets a minimum width the
    /// columns around it cannot take back, and the row runs past the window's edge.
    func clippedToOffer() -> some View {
        GeometryReader { proxy in
            self.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped()
        }
    }

    /// One line that runs out in a fade rather than an ellipsis, as Claude's sidebar titles do.
    /// Fills the width it is given, so nothing flexible should follow it in a row. `minWidth: 0`
    /// is what lets it be narrower than its text: without it a long title keeps the whole row,
    /// and the column around it, as wide as the title.
    func fadedEnd(_ width: CGFloat = 28) -> some View {
        lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            })
    }

    /// A text field: the sheet's grey inside a 1 pt grey rule; pair with `.textFieldStyle(.plain)`.
    func ledgerField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Ledger.field)
            .overlay(Rectangle().strokeBorder(Ledger.ink3.opacity(0.6), lineWidth: Ledger.hairline))
    }
}

/// A section title in the ledger: name, count, and an optional action on the right.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MonoLabel(title, color: Ledger.ink)
            if let count {
                Text("\(count)").font(Ledger.monoFont(11)).foregroundStyle(Ledger.ink3).monospacedDigit()
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, count: Int?) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Echo's mark for the top bar: one solid square and the echoes it sends out, light on a square ink
/// tile that casts the accent's hard offset, with the highlighter's dot; the app icon is too fine to
/// read at this size.
struct EchoMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 32
            context.fill(Path(CGRect(x: 4 * s, y: 4 * s, width: 28 * s, height: 28 * s)), with: .color(Ledger.accent))
            context.fill(Path(CGRect(x: 0, y: 0, width: 28 * s, height: 28 * s)), with: .color(Ledger.markerInk))
            // The mark sits on a 16-unit grid, centred in the tile.
            let unit = 22 * s / 16
            let origin = CGPoint(x: 3 * s, y: 3 * s)
            func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: side * unit, height: side * unit),
                     cornerRadius: radius * unit, style: .continuous)
            }
            let paper = Color(white: 0.985)
            context.stroke(square(7, 1.5, 7.5, 1.8), with: .color(paper.opacity(0.45)), lineWidth: 1.1 * unit)
            context.stroke(square(4.5, 4, 7.5, 1.8), with: .color(paper.opacity(0.7)), lineWidth: 1.1 * unit)
            context.fill(square(1.5, 7, 7.5, 1.8), with: .color(paper))
            context.fill(square(5.6, 11.1, 2, 0.5), with: .color(Ledger.marker))
        }
        .accessibilityHidden(true)
    }
}

/// Makes the window's views resolve the Ledger's colours again after Custom's colours changed.
/// SwiftUI does so only when the colour scheme changes, so the scheme it sees flips for a
/// moment; Ledger colours ignore it while Custom, and the window itself keeps its appearance,
/// so nothing visibly flashes (ui-ux/0037).
struct LookRefresh: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, model.lookFlipped ? (scheme == .dark ? .light : .dark) : scheme)
    }
}

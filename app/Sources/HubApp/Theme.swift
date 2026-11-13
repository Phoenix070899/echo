import AppKit
import HubCore
import SwiftUI

/// The Ledger look in Claude's own app: its warm greys (bg-200 for the window and sidebar, bg-100
/// for the chat canvas, bg-300 for a user's bubble and hovers), near-black ink, a 0.5 pt hairline
/// for borders, and the clay accent for the one action that moves work forward (ui-ux/0085).
enum Ledger {
    /// The window, and the sidebar that sits flat on it.
    static let desk = dynamic(0xF5F4ED, 0x1F1E1D) { $0.background }
    /// The chat canvas and every panel beside it.
    static let paper = dynamic(0xFAF9F5, 0x262624) { $0.surface }
    static let ink = dynamic(0x141413, 0xFAF9F5) { $0.text }
    static let ink2 = dynamic(0x3D3D3A, 0xC2C0B6) { CustomLook.mix($0.text, $0.surface, 0.3) }
    /// The quietest text; still 4.5:1 or better on every fill it sits on.
    static let ink3 = dynamic(0x6B6A64, 0x9C9A92) { CustomLook.mix($0.text, $0.surface, 0.4) }
    /// Claude's border: ink at 15 % on the canvas.
    static let rule = dynamic(0xDDDACF, 0x3F3E3B) { CustomLook.mix($0.surface, $0.text, 0.14) }
    /// A hovered row, and a code block's fill.
    static let wash = dynamic(0xEFEDE4, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.05) }
    /// The row picked in the sidebar.
    static let selected = dynamic(0xE8E6DC, 0x3A3936) { CustomLook.mix($0.surface, $0.accent, 0.12) }
    /// The human's message bubble: Claude's bg-300, darker than the canvas in both modes.
    static let bubble = dynamic(0xF0EEE6, 0x141413) { CustomLook.mix($0.surface, $0.text, 0.07) }
    // Areas are told apart by fills, not lines.
    static let strip = dynamic(0xF5F4ED, 0x1F1E1D) { CustomLook.mix($0.background, $0.surface, 0.4) }
    static let pill = dynamic(0xFAF9F5, 0x30302E) { CustomLook.mix($0.surface, $0.dark ? $0.text : "#ffffff", 0.1) }
    /// A title row's band: none, as Claude's header sits on the canvas.
    static let band = dynamic(0xFAF9F5, 0x262624) { $0.surface }
    /// A Needs you item's card.
    static let needCard = dynamic(0xF7ECDC, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.16) }
    /// Secondary buttons.
    static let fill = dynamic(0xEAE8DE, 0x3A3936) { CustomLook.mix($0.surface, $0.text, 0.09) }
    /// The primary button, and the text on it: Claude's clay, a shade deeper in light mode for 4.5:1
    /// under its cream text.
    static let primary = dynamic(0xBE5638, 0xD97757) { $0.text }
    static let onPrimary = dynamic(0xFFFFFF, 0x141413) { $0.surface }
    /// The message box and text fields: Claude's bg-000.
    static let field = dynamic(0xFFFFFF, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.06) }
    /// The picked one of a few choices, like a mode card.
    static let chosen = dynamic(0xEBDBBC, 0x45402F) { CustomLook.mix($0.surface, $0.accent, 0.22) }
    /// The highlighter, Claude's manilla and kraft. Text on it is always dark ink, in both modes.
    static let marker = dynamic(0xEBDBBC, 0xD4A27F) { $0.highlighter }
    static let markerInk = rgb(0x141413)
    static let markerWash = dynamic(0xF7ECDC, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.14) }
    static let run = dynamic(0x35699B, 0x6A9BCC) { $0.accent }
    static let done = dynamic(0x5B6E42, 0x9BB07C)
    static let fail = dynamic(0xB42318, 0xF2877B)
    /// A file changed but not committed, in the Files column; amber, apart from added green.
    static let changed = dynamic(0x9A6A12, 0xD4A27F)
    /// Lines an agent just changed in an open preview, for a moment.
    static let justChanged = dynamic(0xF5E6C4, 0x3D3320) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.18 : 0.3) }
    static let okWash = dynamic(0xE8EEDD, 0x2B3123)
    static let okInk = dynamic(0x3F5230, 0xBCD0A0)
    static let failWash = dynamic(0xF8E1DC, 0x4A2420)
    static let failInk = dynamic(0x8C1D14, 0xF5B3AA)

    /// Claude's radii (Tailwind's): inner 6 (chips), element 8 (rows, buttons, small fields),
    /// card 12 (bubbles, tool cards, popovers), container 16 (panels and the message box).
    static let radiusInner: CGFloat = 6
    static let radiusElement: CGFloat = 8
    static let radiusCard: CGFloat = 12
    static let radiusContainer: CGFloat = 16
    /// Claude's border is half a point.
    static let hairline: CGFloat = 0.5

    static let mono = Font.system(size: 12, design: .monospaced)

    /// The interface's sans: the system face at the weight asked for.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// `font`'s face as an NSFont, for text AppKit draws.
    static func nsFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight == .medium ? .medium : weight == .semibold ? .semibold : weight == .bold ? .bold : .regular)
    }

    /// The system faces need no registering; kept so launch code stays as it was.
    static func registerFonts() {}

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
        Circle()
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

/// The amber target: something waits on the human.
struct NeedsRing: View {
    var size: CGFloat = 14

    var body: some View {
        Circle().strokeBorder(Ledger.changed, lineWidth: 1.6)
            .overlay(Circle().fill(Ledger.changed).frame(width: size * 0.36, height: size * 0.36))
            .frame(width: size, height: size)
            .accessibilityLabel("Needs you")
    }
}

/// A Worker's mark at the right of its sidebar row (ui-ux/0092): a turning ring while it works (slower
/// while it only waits on background work), an amber target when it needs the human, a filled tick
/// when it is done, a plain grey tick when it ended at its input box, a red cross when it went wrong.
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
                Image(systemName: "checkmark").font(Ledger.font(10, .semibold)).foregroundStyle(Ledger.ink3)
            } else if worker.isTrouble {
                Image(systemName: "xmark.circle.fill").font(Ledger.font(size)).foregroundStyle(Ledger.fail)
            } else {
                Image(systemName: "checkmark.circle.fill").font(Ledger.font(size)).foregroundStyle(Ledger.done)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(worker.phaseLabel)
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
            .background(Ledger.marker, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

/// The ledger's buttons: the clay accent's primary for the action that moves work forward, a quiet fill for
/// the rest; 28 pt tall, or 32 pt when large, on the row radius.
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
            configuration.label
                .font(Ledger.font(14, .medium))
                .lineLimit(1)
                .padding(.horizontal, large ? 14 : 10)
                .frame(minHeight: large ? 32 : 28)
                .foregroundStyle(primary ? Ledger.onPrimary : Ledger.ink)
                .background(primary ? Ledger.primary : Ledger.fill, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
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

/// Claude's segmented control: a grey track, the picked choice on a white thumb. Stands in for
/// the system's segmented picker, whose accent-blue thumb belongs to no other control here.
struct LedgerSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(Ledger.font(12, on ? .medium : .regular))
                        .foregroundStyle(on ? Ledger.ink : Ledger.ink2)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(on ? Ledger.field : .clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                        .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1.5, y: 0.5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Ledger.bubble, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
        .fixedSize()
    }
}

/// A blue text link, for quiet actions like Show all.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ledger.font(13, .medium))
            .foregroundStyle(Ledger.run)
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

    /// A text field filled rather than outlined; pair with `.textFieldStyle(.plain)`.
    func ledgerField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Ledger.field, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
    }
}

/// A section title in the ledger: name, count, and an optional action on the right.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Ledger.font(15, .semibold))
            if let count {
                Text("\(count)").font(Ledger.font(12.5)).foregroundStyle(Ledger.ink3).monospacedDigit()
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

/// Echo's mark for the top bar: one solid square and the echoes it sends out, light on an ink
/// tile, with the highlighter's dot; the app icon is too fine to read at this size.
struct EchoMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 32
            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 32 * s, height: 32 * s), cornerRadius: 8 * s, style: .continuous),
                         with: .color(Ledger.markerInk))
            // The mark sits on a 16-unit grid, centred in the tile.
            let unit = 22 * s / 16
            let origin = CGPoint(x: 5 * s, y: 5 * s)
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

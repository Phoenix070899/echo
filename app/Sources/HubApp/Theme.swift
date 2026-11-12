import AppKit
import HubCore
import SwiftUI

/// The Ledger look in Astryx's neutral theme: a flat grey ramp, white sheets on a light-grey desk,
/// black ink, and a yellow highlighter that only ever means "this needs you". Every colour has a
/// dark-mode twin, each one a value of Astryx's palette or a blend of two (ui-ux/0077).
enum Ledger {
    static let desk = dynamic(0xF1F1F1, 0x1B1B1B) { $0.background }
    static let paper = dynamic(0xFFFFFF, 0x262626) { $0.surface }
    static let ink = dynamic(0x000000, 0xFFFFFF) { $0.text }
    static let ink2 = dynamic(0x474747, 0xC6C6C6) { CustomLook.mix($0.text, $0.surface, 0.3) }
    /// The quietest text; still 4.5:1 or better on every fill it sits on.
    static let ink3 = dynamic(0x6B6B6B, 0x9E9E9E) { CustomLook.mix($0.text, $0.surface, 0.4) }
    static let rule = dynamic(0xEBEBEB, 0x3A3A3A) { CustomLook.mix($0.surface, $0.text, 0.14) }
    static let wash = dynamic(0xF1F1F1, 0x303030) { CustomLook.mix($0.surface, $0.text, 0.05) }
    static let selected = dynamic(0xE2E2E2, 0x3A3A3A) { CustomLook.mix($0.surface, $0.accent, 0.12) }
    // Areas are told apart by fills, not lines.
    /// The strip the repo tabs sit on.
    static let strip = dynamic(0xF1F1F1, 0x1B1B1B) { CustomLook.mix($0.background, $0.surface, 0.4) }
    /// The picked repo tab.
    static let pill = dynamic(0xFFFFFF, 0x303030) { CustomLook.mix($0.surface, $0.dark ? $0.text : "#ffffff", 0.1) }
    /// An agent's header band in the ledger, and a panel's title row.
    static let band = dynamic(0xF6F6F6, 0x202020) { CustomLook.mix($0.background, $0.surface, 0.6) }
    /// A Needs you item's card.
    static let needCard = dynamic(0xFEF6E0, 0x2F2B1C) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.16) }
    /// Secondary buttons.
    static let fill = dynamic(0xEAEAEA, 0x343434) { CustomLook.mix($0.surface, $0.text, 0.09) }
    /// The primary button, and the text on it.
    static let primary = dynamic(0x1B1B1B, 0xF1F1F1) { $0.text }
    static let onPrimary = dynamic(0xFFFFFF, 0x1B1B1B) { $0.surface }
    /// Text fields and pickers.
    static let field = dynamic(0xF1F1F1, 0x1F1F1F) { CustomLook.mix($0.surface, $0.text, 0.06) }
    /// The picked one of a few choices, like a mode card.
    static let chosen = dynamic(0xD4D4D4, 0x474747) { CustomLook.mix($0.surface, $0.accent, 0.22) }
    /// The highlighter. Text on it is always dark ink, in both modes.
    static let marker = dynamic(0xFFCE2F, 0xEEC448) { $0.highlighter }
    static let markerInk = rgb(0x1B1B1B)
    static let markerWash = dynamic(0xFEF6E0, 0x2F2B1C) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.14) }
    static let run = dynamic(0x0074E2, 0x6D9CFE) { $0.accent }
    static let done = dynamic(0x198100, 0x64AF4C)
    static let fail = dynamic(0xC9303A, 0xFF705D)
    /// A file changed but not committed, in the Files column; amber, apart from added green.
    static let changed = dynamic(0x836700, 0xEEC448)
    /// Lines an agent just changed in an open preview, for a moment.
    static let justChanged = dynamic(0xFDEFC4, 0x3A3317) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.18 : 0.3) }
    static let okWash = dynamic(0xE3F2E2, 0x213321)
    static let okInk = dynamic(0x00490B, 0x90CA90)
    static let failWash = dynamic(0xFFE6E3, 0x4A2523)
    static let failInk = dynamic(0x76000C, 0xFFAEA7)

    /// Astryx's radii: inner 6, element 10 (buttons, fields), container 12 (sheets).
    static let radiusInner: CGFloat = 6
    static let radiusElement: CGFloat = 10
    static let radiusContainer: CGFloat = 12

    static let mono = Font.system(size: 12, design: .monospaced)

    /// Astryx's one face, Figtree, used for everything but code: 400 for text, 500 for labels,
    /// 600 for headings and 700 for the heaviest. Falls back to the system face when the font is
    /// not in the app (as in tests).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let wght = Self.wght(weight)
        let key = "\(size)-\(wght)"
        if let font = fonts[key] { return font }
        let font: Font = figtree(size, wght).map(Font.init) ?? .system(size: size, weight: systemWeight(wght))
        fonts[key] = font
        return font
    }

    /// `font`'s face as an NSFont, for text AppKit draws.
    static func nsFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> NSFont {
        let wght = Self.wght(weight)
        return figtree(size, wght) ?? .systemFont(ofSize: size, weight: wght <= 400 ? .regular : wght == 500 ? .medium : wght == 600 ? .semibold : .bold)
    }

    /// The variable axis value for a weight: Astryx's normal, medium, semibold and bold.
    private static func wght(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        default: return 700
        }
    }

    private static func systemWeight(_ wght: Int) -> Font.Weight {
        wght <= 400 ? .regular : wght == 500 ? .medium : wght == 600 ? .semibold : .bold
    }

    /// Figtree at `wght`, if the app has it.
    private static func figtree(_ size: CGFloat, _ wght: Int) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [0x7767_6874: wght]])
        return NSFont(descriptor: descriptor, size: size).flatMap { $0.familyName == family ? $0 : nil }
    }

    private static let family = "Figtree"
    nonisolated(unsafe) private static var fonts: [String: Font] = [:]

    /// Registers Figtree from the app's Resources/Fonts; call once at launch.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
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
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 8, height: 8)
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

/// The ledger's buttons: Astryx's primary for the action that moves work forward, a quiet fill for
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
                .font(Ledger.font(large ? 14 : 13, .medium))
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
    /// A sheet of paper on the desk, set apart by its fill alone, on Astryx's container radius.
    func ledgerSheet() -> some View {
        background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
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
            Text(title).font(Ledger.font(14, .semibold))
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

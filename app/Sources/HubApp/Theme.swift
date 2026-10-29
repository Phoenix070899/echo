import AppKit
import HubCore
import SwiftUI

/// The Ledger look in Lanh's colours: warm greys, white sheets, near-black ink, and a sand
/// highlighter that only ever means "this needs you". Every colour has a dark-mode twin, each one
/// a step of Lanh's palette (ui-ux/0048).
enum Ledger {
    static let desk = dynamic(0xF4F3F4, 0x11100F) { $0.background }
    static let paper = dynamic(0xFFFFFF, 0x1E1C1C) { $0.surface }
    static let ink = dynamic(0x11100F, 0xE6E6E4) { $0.text }
    static let ink2 = dynamic(0x484543, 0xB0AEA9) { CustomLook.mix($0.text, $0.surface, 0.3) }
    /// The quietest text; still 4.5:1 or better on every fill it sits on.
    static let ink3 = dynamic(0x605E5B, 0x898682) { CustomLook.mix($0.text, $0.surface, 0.4) }
    static let rule = dynamic(0xE6E6E4, 0x302E2D) { CustomLook.mix($0.surface, $0.text, 0.14) }
    static let wash = dynamic(0xF1F1F0, 0x2A2828) { CustomLook.mix($0.surface, $0.text, 0.05) }
    static let selected = dynamic(0xE8E7E7, 0x323030) { CustomLook.mix($0.surface, $0.accent, 0.12) }
    // Areas are told apart by fills, not lines.
    /// The strip the repo tabs sit on.
    static let strip = dynamic(0xF4F3F4, 0x11100F) { CustomLook.mix($0.background, $0.surface, 0.4) }
    /// The picked repo tab.
    static let pill = dynamic(0xFFFFFF, 0x302E2D) { CustomLook.mix($0.surface, $0.dark ? $0.text : "#ffffff", 0.1) }
    /// An agent's header band in the ledger, and a panel's title row.
    static let band = dynamic(0xF4F3F4, 0x181616) { CustomLook.mix($0.background, $0.surface, 0.6) }
    /// A Needs you item's card.
    static let needCard = dynamic(0xFAF1E2, 0x2B241A) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.16) }
    /// Secondary buttons.
    static let fill = dynamic(0xF1F1F0, 0x2A2828) { CustomLook.mix($0.surface, $0.text, 0.09) }
    /// The primary button, and the text on it.
    static let primary = dynamic(0x302E2D, 0x898682) { $0.text }
    static let onPrimary = dynamic(0xFFFFFF, 0x1E1C1C) { $0.surface }
    /// Text fields and pickers.
    static let field = dynamic(0xF4F3F4, 0x262424) { CustomLook.mix($0.surface, $0.text, 0.06) }
    /// The picked one of a few choices, like a mode card.
    static let chosen = dynamic(0xE8E7E7, 0x323030) { CustomLook.mix($0.surface, $0.accent, 0.22) }
    /// The highlighter. Text on it is always dark ink, in both modes.
    static let marker = dynamic(0xF3DBBA, 0xE7BD80) { $0.highlighter }
    static let markerInk = rgb(0x11100F)
    static let markerWash = dynamic(0xFAF1E2, 0x2B241A) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.14) }
    static let run = dynamic(0x016FB1, 0x84CEF2) { $0.accent }
    static let done = dynamic(0x019D4D, 0x94D6AA)
    static let fail = dynamic(0xD74745, 0xF9AFA6)
    /// A file changed but not committed, in the Files column; amber, apart from added green.
    static let changed = dynamic(0xBD6A01, 0xE7BD80)
    /// Lines an agent just changed in an open preview, for a moment.
    static let justChanged = dynamic(0xFAF1E2, 0x3A2F1E) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.18 : 0.3) }
    static let okWash = dynamic(0xE8F6EC, 0x013512)
    static let okInk = dynamic(0x006222, 0xC5E9D1)
    static let failWash = dynamic(0xFEEDEA, 0x4C1010)
    static let failInk = dynamic(0x8C1A1F, 0xFED3CC)

    static let mono = Font.system(size: 12, design: .monospaced)

    /// Lanh's one face, used for everything but code: 350 for text, 500 for anything heavier.
    /// Falls back to the system face when the font is not in the app (as in tests).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let light: [Font.Weight] = [.ultraLight, .thin, .light, .regular]
        let wght = light.contains(weight) ? 350 : 500
        let key = "\(size)-\(wght)"
        if let font = fonts[key] { return font }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [0x7767_6874: wght]])
        let font: Font = NSFont(descriptor: descriptor, size: size).flatMap { $0.familyName == family ? Font($0) : nil }
            ?? .system(size: size, weight: wght == 350 ? .regular : .medium)
        fonts[key] = font
        return font
    }

    private static let family = "Google Sans Flex 18pt"
    nonisolated(unsafe) private static var fonts: [String: Font] = [:]

    /// Registers Google Sans Flex from the app's Resources/Fonts; call once at launch.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "woff2" {
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
    /// Running blue, done green, ended grey, anything that settled badly red.
    var markColor: Color {
        if isActive { return Ledger.run }
        if phase == "ended" { return Ledger.ink3 }
        return isTrouble ? Ledger.fail : Ledger.done
    }

    /// "Running", "Waiting", "Done", "Ended", "Blocked", "Exited", "Lost".
    var phaseLabel: String {
        if isActive { return state == .waiting ? "Waiting" : "Running" }
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

/// The ledger's buttons: Lanh's primary for the action that moves work forward, a quiet fill for
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
                .background(primary ? Ledger.primary : Ledger.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    /// A sheet of paper on the desk, set apart by its fill alone, on Lanh's panel radius.
    func ledgerSheet() -> some View {
        background(Ledger.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// A text field filled rather than outlined; pair with `.textFieldStyle(.plain)`.
    func ledgerField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Ledger.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

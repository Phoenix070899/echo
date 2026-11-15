import AppKit
import HubCore
import SwiftUI

/// The Ledger look in Foundry, the human's design system (ui-ux/0104): a pale concrete desk, a
/// lighter sheet for panels, near-black ink, 1 pt rules, square corners, and a muted safety orange
/// that marks things but is never text. Dark mode keeps the values it had before Foundry.
public enum Ledger {
    /// The window, and the sidebar that sits flat on it.
    public static let desk = dynamic(0xE6E4DF, 0x1F1E1D) { $0.background }
    /// The chat canvas and every panel beside it.
    public static let paper = dynamic(0xEFEEEA, 0x262624) { $0.surface }
    public static let ink = dynamic(0x2B2B29, 0xFAF9F5) { $0.text }
    public static let ink2 = dynamic(0x45433F, 0xC2C0B6) { CustomLook.mix($0.text, $0.surface, 0.3) }
    /// The quietest text; still 4.5:1 or better on every fill it sits on.
    public static let ink3 = dynamic(0x5E5B55, 0x9C9A92) { CustomLook.mix($0.text, $0.surface, 0.4) }
    /// Foundry's line: dividers between rows and around sheets.
    public static let rule = dynamic(0xC2BEB5, 0x3F3E3B) { CustomLook.mix($0.surface, $0.text, 0.14) }
    /// A list row's grey square (ui-ux/0124), darker than the rule so it reads as a mark.
    public static let square = dynamic(0x8A857B, 0x6E6C66) { CustomLook.mix($0.surface, $0.text, 0.45) }
    /// A hovered row, and a code block's fill.
    public static let wash = dynamic(0xDFDCD6, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.05) }
    /// The row picked in the sidebar; `accent` marks its leading edge.
    public static let selected = dynamic(0xD8D5CE, 0x3A3936) { CustomLook.mix($0.surface, $0.accent, 0.12) }
    /// The human's message bubble: the sunk grey, darker than the canvas in both modes.
    public static let bubble = dynamic(0xD8D5CE, 0x141413) { CustomLook.mix($0.surface, $0.text, 0.07) }
    /// The human's own message: ink in light mode, near black in dark, with white text (ui-ux/0134).
    public static let sent = dynamic(0x2B2B29, 0x141413) { $0.dark ? CustomLook.mix($0.surface, "#000000", 0.5) : $0.text }
    public static let onSent = rgb(0xFFFFFF)
    // Areas are told apart by fills and rules.
    public static let strip = dynamic(0xE6E4DF, 0x1F1E1D) { CustomLook.mix($0.background, $0.surface, 0.4) }
    public static let pill = dynamic(0xEFEEEA, 0x30302E) { CustomLook.mix($0.surface, $0.dark ? $0.text : "#ffffff", 0.1) }
    /// A title row's band: the desk, so a tab strip reads as a strip above its sheet.
    public static let band = dynamic(0xE6E4DF, 0x262624) { $0.surface }
    /// A Needs you item's card.
    public static let needCard = dynamic(0xF2DDCD, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.16) }
    /// Chips and other quiet fills.
    public static let fill = dynamic(0xD8D5CE, 0x3A3936) { CustomLook.mix($0.surface, $0.text, 0.09) }
    /// The primary button, and the text on it: Foundry's ink, its accent shown as a hard offset.
    public static let primary = dynamic(0x2B2B29, 0xD97757) { $0.text }
    public static let onPrimary = dynamic(0xEFEEEA, 0x141413) { $0.surface }
    /// The message box and text fields: the sheet's grey inside an ink or grey rule.
    public static let field = dynamic(0xEFEEEA, 0x30302E) { CustomLook.mix($0.surface, $0.text, 0.06) }
    /// The picked one of a few choices, like a mode card.
    public static let chosen = dynamic(0xEBC9B0, 0x45402F) { CustomLook.mix($0.surface, $0.accent, 0.22) }
    /// Foundry's muted safety orange: marks, meters, the picked row's edge, the button's offset. Never
    /// text in light mode (3.1:1 on the sheet).
    public static let accent = dynamic(0xC8642E, 0xD9773F) { $0.accent }
    /// The accent a shade deeper, the same in both modes, so white text on it is 4.7:1: a chat
    /// reply that needs the human (ui-ux/0134).
    public static let accentDeep = dynamic(0xB45A29, 0xB45A29) { CustomLook.mix($0.accent, "#000000", 0.1) }
    /// The hard block a raised sheet casts (a menu, a modal): ink in light mode, black in dark,
    /// where ink is the light text colour.
    public static let cast = dynamic(0x2B2B29, 0x000000)
    /// The highlighter. Text on it is always dark ink, in both modes.
    public static let marker = dynamic(0xEBC9B0, 0xD4A27F) { $0.highlighter }
    public static let markerInk = rgb(0x2B2B29)
    public static let markerWash = dynamic(0xF2DDCD, 0x3A3024) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.12 : 0.14) }
    public static let run = dynamic(0x3F6A92, 0x6A9BCC) { $0.accent }
    public static let done = dynamic(0x5B6E42, 0x9BB07C)
    public static let fail = dynamic(0xA33A2A, 0xF2877B)
    /// A file changed but not committed, in the Files column; amber, apart from added green.
    public static let changed = dynamic(0x8A5E12, 0xD4A27F)
    /// Lines an agent just changed in an open preview, for a moment.
    public static let justChanged = dynamic(0xF0DFC7, 0x3D3320) { CustomLook.mix($0.surface, $0.highlighter, $0.dark ? 0.18 : 0.3) }
    public static let okWash = dynamic(0xE3E8D6, 0x2B3123)
    public static let okInk = dynamic(0x3F5230, 0xBCD0A0)
    public static let failWash = dynamic(0xF1DCD5, 0x4A2420)
    public static let failInk = dynamic(0x8C1D14, 0xF5B3AA)

    /// Foundry is square: every radius is 0. The names stay so each view keeps saying which kind of
    /// shape it is.
    public static let radiusInner: CGFloat = 0
    public static let radiusElement: CGFloat = 0
    public static let radiusCard: CGFloat = 0
    public static let radiusContainer: CGFloat = 0
    /// Foundry's rule is a full point; section and control frames are `ruleStrong`.
    public static let hairline: CGFloat = 1
    public static let ruleStrong: CGFloat = 2

    /// The faces Echo bundles (ui-ux/0104): Archivo for the interface, JetBrains Mono for code,
    /// labels and readouts. A face that is missing falls back to the system's.
    public static let sansFamily = "Archivo"
    public static let monoFamily = "JetBrains Mono"

    public static let mono = monoFont(12)

    /// The interface's sans: Archivo at the weight asked for.
    public static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(sansFamily, fixedSize: size).weight(weight)
    }

    /// Code, paths and readouts: JetBrains Mono.
    public static func monoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, fixedSize: size).weight(weight)
    }

    /// Titles: Archivo at its heaviest, 75 % wide, set in capitals by the view.
    public static func display(_ size: CGFloat) -> Font {
        Font(variable(sansFamily, size, weight: 800, width: 75) ?? .systemFont(ofSize: size, weight: .heavy))
    }

    /// `font`'s face as an NSFont, for text AppKit draws.
    public static func nsFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> NSFont {
        variable(sansFamily, size, weight: axisWeight(weight))
            ?? .systemFont(ofSize: size, weight: weight == .medium ? .medium : weight == .semibold ? .semibold : weight == .bold ? .bold : .regular)
    }

    /// `monoFont`'s face as an NSFont.
    public static func nsMono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
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
    public static func registerFonts() {
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
    nonisolated(unsafe) public private(set) static var custom: CustomLook?

    /// Sets the whole app's appearance (nil follows macOS) and Custom's colours; true when the
    /// colours changed, so views must resolve them again (`LookRefresh`).
    @MainActor @discardableResult
    public static func apply(custom: CustomLook?, appearance name: NSAppearance.Name?) -> Bool {
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

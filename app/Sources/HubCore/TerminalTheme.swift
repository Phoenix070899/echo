import Foundation

/// A terminal colour scheme: the 16 ANSI colours plus background, text, cursor, and selection,
/// and optionally the text under the cursor, selected text, and bold text. Colours are `#rrggbb`.
public struct TerminalTheme: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var background: String
    public var foreground: String
    public var cursor: String
    public var selection: String
    /// black, red, green, yellow, blue, magenta, cyan, white, then the bright eight.
    public var ansi: [String]
    /// The text under the cursor; nil lets the terminal pick.
    public var cursorText: String?
    /// Selected text; nil keeps each cell's own colour.
    public var selectionText: String?
    /// Bold text; nil draws it in its cell's colour.
    public var bold: String?

    public var id: String { name }

    public init(name: String, background: String, foreground: String, cursor: String, selection: String, ansi: [String],
                cursorText: String? = nil, selectionText: String? = nil, bold: String? = nil) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
        self.cursorText = cursorText
        self.selectionText = selectionText
        self.bold = bold
    }

    /// Whether its background is dark, so the window around it should be too.
    public var isDark: Bool {
        guard let c = Self.rgb(background) else { return true }
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.5
    }

    public static let ayuDark = TerminalTheme(
        name: "Ayu Dark", background: "#0a0e14", foreground: "#b3b1ad", cursor: "#e6b450", selection: "#273747",
        ansi: ["#01060e", "#ea6c73", "#91b362", "#f9af4f", "#53bdfa", "#fae994", "#90e1c6", "#c7c7c7",
               "#686868", "#f07178", "#c2d94c", "#ffb454", "#59c2ff", "#ffee99", "#95e6cb", "#ffffff"]
    )

    public static let tangoLight = TerminalTheme(
        name: "Tango Light", background: "#ffffff", foreground: "#2e3434", cursor: "#2e3434", selection: "#accef7",
        ansi: ["#2e3436", "#cc0000", "#4e9a06", "#8e7700", "#3465a4", "#75507b", "#05727e", "#6a6a6a",
               "#555753", "#ef2929", "#1b7a1b", "#6d5a00", "#204a87", "#ad7fa8", "#034b50", "#3d3d3d"]
    )

    /// The Hub's first look: a neutral dark with the xterm palette.
    public static let hubDark = TerminalTheme(
        name: "Hub Dark", background: "#171a1f", foreground: "#e0e0e0", cursor: "#0a84ff", selection: "#264f78",
        ansi: ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
               "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#e5e5e5"]
    )

    /// Foundry's Ledger in light mode (ui-ux/0104): ink on the sheet, the safety orange cursor, the
    /// highlighter for selections, and done, failed, changed, and running for green, red, yellow,
    /// and blue. Every colour but black's dark twin reads at 4.5:1 or better.
    public static let foundryLight = TerminalTheme(
        name: "Foundry Light", background: "#efeeea", foreground: "#2b2b29", cursor: "#c8642e", selection: "#ebc9b0",
        ansi: ["#2b2b29", "#a33a2a", "#5b6e42", "#8a5e12", "#3f6a92", "#7e4a72", "#2e6b68", "#5e5b55",
               "#6b6760", "#a8472a", "#4a6a2e", "#855e00", "#2f5a86", "#93507f", "#1f7570", "#2b2b29"],
        cursorText: "#efeeea", selectionText: "#2b2b29"
    )

    /// Foundry's Ledger in dark mode, the same roles on the dark sheet.
    public static let foundryDark = TerminalTheme(
        name: "Foundry Dark", background: "#262624", foreground: "#faf9f5", cursor: "#d9773f", selection: "#45402f",
        ansi: ["#3f3e3b", "#f2877b", "#9bb07c", "#d4a27f", "#6a9bcc", "#c49bbf", "#8cbfb8", "#c2c0b6",
               "#9c9a92", "#f5b3aa", "#bcd0a0", "#e8c08f", "#9cc0e3", "#ddb8d8", "#b0d8d2", "#faf9f5"],
        cursorText: "#262624"
    )

    public static let dracula = TerminalTheme(
        name: "Dracula", background: "#282a36", foreground: "#f8f8f2", cursor: "#f8f8f2", selection: "#44475a",
        ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
               "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]
    )

    public static let nord = TerminalTheme(
        name: "Nord", background: "#2e3440", foreground: "#d8dee9", cursor: "#eceff4", selection: "#434c5e",
        ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
               "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]
    )

    public static let gruvboxDark = TerminalTheme(
        name: "Gruvbox Dark", background: "#282828", foreground: "#ebdbb2", cursor: "#ebdbb2", selection: "#504945",
        ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
               "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]
    )

    public static let catppuccinMocha = TerminalTheme(
        name: "Catppuccin Mocha", background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc", selection: "#585b70",
        ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
               "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
    )

    public static let tokyoNight = TerminalTheme(
        name: "Tokyo Night", background: "#1a1b26", foreground: "#c0caf5", cursor: "#c0caf5", selection: "#33467c",
        ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
               "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]
    )

    public static let oneDark = TerminalTheme(
        name: "One Dark", background: "#282c34", foreground: "#abb2bf", cursor: "#528bff", selection: "#3e4451",
        ansi: ["#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
               "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"]
    )

    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark", background: "#002b36", foreground: "#839496", cursor: "#93a1a1", selection: "#073642",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
    )

    public static let solarizedLight = TerminalTheme(
        name: "Solarized Light", background: "#fdf6e3", foreground: "#657b83", cursor: "#586e75", selection: "#eee8d5",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
    )

    public static let presets = [foundryLight, foundryDark, ayuDark, tangoLight, hubDark, dracula, nord, gruvboxDark, catppuccinMocha, tokyoNight,
                                 oneDark, solarizedDark, solarizedLight]

    /// The ANSI colours' names, in `ansi` order.
    public static let ansiNames: [String] = {
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        return names + names.map { "Bright " + $0.lowercased() }
    }()

    /// Red, green, and blue in 0...1, or nil for anything but `#rrggbb`.
    public static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }

    /// `#rrggbb` for colour components in 0...1.
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        let byte = { (v: Double) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}

/// The terminal look the human chose: a preset, their colour overrides, the font, and an
/// optional image behind every terminal.
public struct TerminalAppearance: Codable, Equatable, Sendable {
    public var theme: TerminalTheme
    public var fontName: String
    public var fontSize: Double
    /// The image file drawn behind every terminal; nil for the plain theme background.
    public var backgroundImage: String?
    /// How much of the theme background covers the image, 0...1, so text stays readable.
    public var backgroundImageDim: Double
    /// Blur radius for the image in points; 0 keeps it sharp.
    public var backgroundImageBlur: Double
    /// How much of its colour dim text keeps, 0...1; Ghostty's own is half (bugs/0093).
    public var faintOpacity: Double
    /// The contrast text keeps against its cell, 1...7: below it, text is drawn black or white.
    /// 1 leaves every colour as it is.
    public var minimumContrast: Double

    public static let defaultImageDim = 0.7
    public static let defaultFaintOpacity = 0.7
    public static let defaultMinimumContrast = 3.0

    /// Echo's first look: Ayu Dark in JetBrainsMono Nerd Font 14.
    public static let standard = TerminalAppearance(theme: .ayuDark, fontName: "JetBrainsMono Nerd Font", fontSize: 14)

    public init(theme: TerminalTheme, fontName: String, fontSize: Double,
                backgroundImage: String? = nil, backgroundImageDim: Double = defaultImageDim,
                backgroundImageBlur: Double = 0, faintOpacity: Double = defaultFaintOpacity,
                minimumContrast: Double = defaultMinimumContrast) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
        self.backgroundImage = backgroundImage
        self.backgroundImageDim = backgroundImageDim
        self.backgroundImageBlur = backgroundImageBlur
        self.faintOpacity = faintOpacity
        self.minimumContrast = minimumContrast
    }

    /// A look saved before background images, dim text, or contrast still loads, with their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(theme: try c.decode(TerminalTheme.self, forKey: .theme),
                  fontName: try c.decode(String.self, forKey: .fontName),
                  fontSize: try c.decode(Double.self, forKey: .fontSize),
                  backgroundImage: try c.decodeIfPresent(String.self, forKey: .backgroundImage),
                  backgroundImageDim: try c.decodeIfPresent(Double.self, forKey: .backgroundImageDim) ?? Self.defaultImageDim,
                  backgroundImageBlur: try c.decodeIfPresent(Double.self, forKey: .backgroundImageBlur) ?? 0,
                  faintOpacity: try c.decodeIfPresent(Double.self, forKey: .faintOpacity) ?? Self.defaultFaintOpacity,
                  minimumContrast: try c.decodeIfPresent(Double.self, forKey: .minimumContrast) ?? Self.defaultMinimumContrast)
    }
}

extension TerminalAppearance {
    /// The look as a libghostty config file. Ghostty's own key bindings are cleared, so Echo's
    /// shortcuts reach its menus; only copy, paste, select all, find, and the line-editing keys
    /// Terminal.app has stay with the terminal.
    public var ghosttyConfig: String {
        var lines = [
            "font-family = \(fontName.replacingOccurrences(of: "\"", with: ""))",
            "font-size = \(fontSize)",
            "background = \(theme.background)",
            "foreground = \(theme.foreground)",
            "cursor-color = \(theme.cursor)",
            "selection-background = \(theme.selection)",
        ]
        if let cursorText = theme.cursorText { lines.append("cursor-text = \(cursorText)") }
        if let selectionText = theme.selectionText { lines.append("selection-foreground = \(selectionText)") }
        if let bold = theme.bold { lines.append("bold-color = \(bold)") }
        lines += theme.ansi.prefix(16).enumerated().map { "palette = \($0.offset)=\($0.element)" }
        lines += [
            // With an image, the default background is clear and the image behind the pane shows
            // through; coloured cells, the cursor, and selections stay solid.
            "background-opacity = \(backgroundImage == nil ? 1 : 0)",
            // A program that assumes a dark terminal draws default text on a grey fill; below 3:1
            // the text flips to black or white (bugs/0093).
            "minimum-contrast = \(minimumContrast)",
            "faint-opacity = \(faintOpacity)",
            "macos-option-as-alt = true",
            "cursor-style-blink = false",
            "shell-integration = none",
            "term = xterm-256color",
            "confirm-close-surface = false",
            "clipboard-read = deny",
            "clipboard-write = allow",
            "clipboard-paste-protection = false",
            "window-padding-x = 0",
            "window-padding-y = 0",
            "keybind = clear",
            "keybind = super+c=copy_to_clipboard",
            "keybind = super+v=paste_from_clipboard",
            "keybind = super+a=select_all",
            "keybind = super+f=start_search",
            "keybind = super+left=text:\\x01",
            "keybind = super+right=text:\\x05",
            "keybind = super+backspace=text:\\x15",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The human's own colours for Echo itself, when Window's Appearance is Custom (ui-ux/0036): five
/// picked colours and a light or dark base; every other shade of the Ledger is mixed from them.
public struct CustomLook: Codable, Equatable, Sendable, Identifiable {
    /// A preset's name, or "Custom" once a colour is changed by hand.
    public var name: String
    /// Light or dark system controls, and the done, failed, and changed colours of that mode.
    public var dark: Bool
    /// Behind everything: the window and its columns.
    public var background: String
    /// Cards, panels, and the ledger.
    public var surface: String
    public var text: String
    /// Running agents and Workers, links, and the picked row.
    public var accent: String
    /// What needs you.
    public var highlighter: String

    public var id: String { name }

    public init(name: String, dark: Bool, background: String, surface: String, text: String, accent: String, highlighter: String) {
        self.name = name
        self.dark = dark
        self.background = background
        self.surface = surface
        self.text = text
        self.accent = accent
        self.highlighter = highlighter
    }

    /// Echo's own Ledger colours, in Claude's palette, to start from.
    public static let light = CustomLook(
        name: "Echo Light", dark: false, background: "#f0eee6", surface: "#faf9f5", text: "#141413", accent: "#35699b", highlighter: "#ebdbbc"
    )
    public static let dark = CustomLook(
        name: "Echo Dark", dark: true, background: "#1f1e1d", surface: "#262624", text: "#f0eee6", accent: "#6a9bcc", highlighter: "#d4a27f"
    )

    /// Echo's own looks, then one made from each terminal preset.
    public static let presets = [light, dark] + TerminalTheme.presets.map { from($0) }

    /// Echo coloured like a terminal theme: its background and text, a panel a shade toward the
    /// text, its blue for accent, and its yellow (a bright one on light themes) for the highlighter.
    public static func from(_ theme: TerminalTheme) -> CustomLook {
        let dark = theme.isDark
        return CustomLook(
            name: theme.name,
            dark: dark,
            background: theme.background,
            surface: mix(theme.background, theme.foreground, 0.05),
            text: theme.foreground,
            accent: theme.ansi[dark ? 12 : 4],
            highlighter: dark ? theme.ansi[11] : "#ffe347"
        )
    }

    /// `a` moved `amount` of the way to `b`, in sRGB.
    public static func mix(_ a: String, _ b: String, _ amount: Double) -> String {
        guard let x = TerminalTheme.rgb(a), let y = TerminalTheme.rgb(b) else { return a }
        let t = min(max(amount, 0), 1)
        return TerminalTheme.hex(
            red: x.red + (y.red - x.red) * t,
            green: x.green + (y.green - x.green) * t,
            blue: x.blue + (y.blue - x.blue) * t
        )
    }
}

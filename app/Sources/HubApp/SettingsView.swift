import AppKit
import Foundry
import HubCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings, one section each: the window's look, the terminal theme (a preset, then any colour changed
/// by hand, the palette's included), its background image, the font, the multiplexer agents run inside, the Teams (with
/// what agents run with and the Orchestrator's rules under Defaults), the Profiles, and Echo Remote.
struct SettingsView: View {
    let section: SettingsSection
    @EnvironmentObject private var model: AppModel
    /// The Custom look being edited; it reaches the app only on Apply.
    @StateObject private var draft = LookDraft()
    @StateObject private var agents = AgentSettingsModel()

    var body: some View {
        switch section {
        case .window:
            page {
                SettingsGroup {
                    SettingsRow("Appearance") {
                        SquarePicker(selection: $model.windowLook, options: WindowLook.allCases.map { ($0, $0.title) }, label: "Appearance")
                        if model.windowLook == .matchTerminal {
                            SettingsNote(model.appearance.theme.isDark
                                         ? "Dark, because the terminal theme is dark."
                                         : "Light, because the terminal theme is light.")
                        }
                    }
                }
                if model.windowLook == .custom {
                    SettingsGroup("Custom") {
                        SettingsRow("Preset") {
                            SquarePicker(selection: lookPresetBinding, options: lookPresetOptions, label: "Preset")
                        }
                        SettingsRow("Mode") {
                            LedgerSegmented(selection: lookBinding(\.dark), options: [(value: false, title: "Light"), (value: true, title: "Dark")])
                            SettingsNote("Mode sets the system controls and the done, failed, and changed colours.")
                        }
                        SettingsRow("Background") { SquareColorWell(selection: lookColour(\.background), label: "Background") }
                        SettingsRow("Surface") { SquareColorWell(selection: lookColour(\.surface), label: "Surface") }
                        SettingsRow("Text") { SquareColorWell(selection: lookColour(\.text), label: "Text") }
                        SettingsRow("Accent") { SquareColorWell(selection: lookColour(\.accent), label: "Accent") }
                        SettingsRow("Highlighter") {
                            SquareColorWell(selection: lookColour(\.highlighter), label: "Highlighter")
                            SettingsNote("Lines, fields, and cards are mixed from these.")
                        }
                        SettingsRow("Match") {
                            Button("Match the Terminal Theme (\(model.appearance.theme.name))") {
                                draft.look = CustomLook.from(model.appearance.theme)
                            }
                            .buttonStyle(.settings)
                        }
                        SettingsRow {
                            HStack(spacing: 10) {
                                SettingsNote(draft.look == model.customLook ? "Applied." : "Not applied yet.")
                                Button("Revert") { draft.look = model.customLook }
                                    .buttonStyle(.settings)
                                    .disabled(draft.look == model.customLook)
                                Button("Apply") { model.customLook = draft.look }
                                    .buttonStyle(.settingsPrimary)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(draft.look == model.customLook)
                            }
                        }
                    }
                }
            }
            .onAppear { draft.look = model.customLook }
        case .theme:
            page {
                SettingsGroup {
                    SettingsRow("Preset") {
                        SquarePicker(selection: presetBinding, options: presetOptions, label: "Preset")
                    }
                    SettingsRow("Background") { SquareColorWell(selection: colour(\.background), label: "Background") }
                    SettingsRow("Text") { SquareColorWell(selection: colour(\.foreground), label: "Text") }
                    SettingsRow("Cursor") { SquareColorWell(selection: colour(\.cursor), label: "Cursor") }
                    SettingsRow("Selection") { SquareColorWell(selection: colour(\.selection), label: "Selection") }
                    optionalRow("Cursor text", \.cursorText, auto: \.background,
                                note: "Auto: the terminal picks it.")
                    optionalRow("Selected text", \.selectionText, auto: \.foreground,
                                note: "Auto: selected text keeps its own colour.")
                    optionalRow("Bold", \.bold, auto: \.foreground,
                                note: "Auto: bold text keeps its own colour.")
                    SettingsRow("Prompt bar") {
                        SquareColorWell(selection: ansiColour(8), label: "Prompt bar")
                        SettingsNote("Bright black in the palette. Claude Code draws your sent prompts on it; their text is the theme's Text, turned black or white below Contrast.")
                    }
                    SettingsRow("Links") {
                        SquareColorWell(selection: ansiColour(4), label: "Links")
                        SettingsNote("Blue in the palette. Claude Code draws links and file paths in it.")
                    }
                    SettingsRow("Contrast") {
                        HStack(spacing: 14) {
                            SquareSlider(value: $model.appearance.minimumContrast, range: 1...7, label: "Contrast")
                            readout(model.appearance.minimumContrast < 1.05 ? "Off"
                                    : String(format: "%.1f:1", model.appearance.minimumContrast))
                        }
                        SettingsNote("Text that reads below this against what is behind it is drawn black or white. 4.5:1 is easy to read; Off keeps every colour.")
                    }
                    SettingsRow("Dim text") {
                        HStack(spacing: 14) {
                            SquareSlider(value: $model.appearance.faintOpacity, range: 0.3...1, label: "Dim text")
                            readout("\(Int((model.appearance.faintOpacity * 100).rounded()))%")
                        }
                        SettingsNote("How much of its colour dim text keeps, like Claude Code's \"Ran 1 shell command\".")
                    }
                    SettingsRow("Palette") {
                        Swatches(theme: model.appearance.theme, colour: ansiColour)
                            .alignmentGuide(.firstTextBaseline) { $0[.top] + 19 }
                        SettingsNote("Click a colour to change it. The top row is normal, the bottom row bright.")
                    }
                }
            }
        case .background:
            page {
                SettingsGroup {
                    SettingsRow("Image") {
                        Text(model.appearance.backgroundImage.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                            .font(Ledger.font(17))
                            .foregroundStyle(Ledger.ink3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 10) {
                            Button("Choose", action: chooseImage)
                                .buttonStyle(.settings)
                            if model.appearance.backgroundImage != nil {
                                Button("Remove") { model.appearance.backgroundImage = nil }
                                    .buttonStyle(.settings)
                            }
                        }
                        if let path = model.appearance.backgroundImage, !FileManager.default.fileExists(atPath: path) {
                            SettingsNote("The image is gone; terminals show the theme background.", problem: true)
                        }
                    }
                    // Always shown, so the controls can be found before an image is chosen.
                    Group {
                        SettingsRow("Dim") {
                            HStack(spacing: 14) {
                                SquareSlider(value: $model.appearance.backgroundImageDim, range: 0.3...0.95, label: "Dim")
                                readout("\(Int((model.appearance.backgroundImageDim * 100).rounded()))%")
                            }
                        }
                        SettingsRow("Blur") {
                            HStack(spacing: 14) {
                                SquareSlider(value: $model.appearance.backgroundImageBlur, range: 0...30, label: "Blur")
                                readout("\(Int(model.appearance.backgroundImageBlur.rounded())) pt")
                            }
                        }
                    }
                    .disabled(model.appearance.backgroundImage == nil)
                    SettingsRow("About") {
                        SettingsNote("Choose an image to show behind every terminal. Text and coloured cells stay solid; dim or blur the image until the text reads easily.", size: 17)
                    }
                }
            }
        case .font:
            page {
                SettingsGroup {
                    SettingsRow("Family") {
                        TextField("Family", text: $model.appearance.fontName)
                            .labelsHidden()
                            .squareField()
                        if NSFont(name: model.appearance.fontName, size: 12) == nil {
                            SettingsNote("Not installed; the system monospaced font is used.", problem: true)
                        }
                    }
                    SettingsRow("Size") {
                        let size = model.appearance.fontSize
                        SquareStepper(text: "\(size.formatted()) pt",
                                      minus: size > 9 ? { model.appearance.fontSize = max(9, size - 0.5) } : nil,
                                      plus: size < 28 ? { model.appearance.fontSize = min(28, size + 0.5) } : nil,
                                      label: "Size")
                    }
                }
            }
        case .multiplexer:
            page {
                SettingsGroup {
                    SettingsRow("Show agents and Workers inside") {
                        SquarePicker(selection: $model.multiplexer.kind, options: Multiplexer.allCases.map { ($0, $0.title) },
                                     label: "Show agents and Workers inside")
                    }
                    if model.multiplexer.kind == .custom {
                        SettingsRow("Command") {
                            TextField("Command", text: $model.multiplexer.command, axis: .vertical)
                                .labelsHidden()
                                .lineLimit(1...3)
                                .squareField(mono: true)
                        }
                    } else if model.multiplexer.enabled {
                        SettingsRow("Command") {
                            Text(model.multiplexer.command)
                                .font(Ledger.monoFont(13))
                                .foregroundStyle(Ledger.ink3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    SettingsRow("How") {
                        SettingsNote(help, size: 17)
                        SettingsNote("A change applies to terminals opened after it.")
                    }
                }
            }
        case .teams:
            TeamsSection(teams: model.teamSettings, agents: agents)
            .onAppear {
                agents.refresh()
                refreshTeams()
            }
        case .profiles:
            ProfilesSection(profiles: model.profileSettings)
                .onAppear {
                    model.profileSettings.repo = model.selectedRepo
                    model.profileSettings.refresh()
                }
        case .providers:
            page { ProvidersSettings() }
        case .worktrees:
            page { WorktreeSettings() }
        case .memory:
            page { MemorySettings() }
        case .remote:
            page { RemoteSettings() }
        }
    }

    /// A slider's value, in mono at its right.
    private func readout(_ text: String) -> some View {
        Text(text)
            .font(Ledger.monoFont(13))
            .foregroundStyle(Ledger.ink3)
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)
    }

    private var presetOptions: [(value: String, title: String)] {
        TerminalTheme.presets.map { ($0.name, $0.name) } + (isPreset ? [] : [("Custom", "Custom")])
    }

    private var lookPresetOptions: [(value: String, title: String)] {
        CustomLook.presets.map { ($0.name, $0.name) } + (isLookPreset ? [] : [("Custom", "Custom")])
    }

    /// Teams are the selected repo's, its own included.
    private func refreshTeams() {
        model.teamSettings.repo = model.selectedRepo
        model.teamSettings.refresh()
    }

    /// One section's page: its head and groups, scrolling when taller than the window.
    private func page<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        SettingsSheetPage(section: section, content: content)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to show behind every terminal"
        if panel.runModal() == .OK, let url = panel.url {
            model.appearance.backgroundImage = url.path
        }
    }

    private var help: String {
        switch model.multiplexer.kind {
        case .tmux:
            return "Each agent or Worker gets its own tmux session, like echo-lanh-a3, with it in the first pane. Split and add windows beside it as usual (⌘D splits right, ⇧⌘D down). Ctrl-] in the agent's pane stops showing it there."
        case .screen:
            return "Each agent or Worker gets its own screen session, like echo-lanh-a3. Use screen's own keys to split; ⌘D is for tmux only."
        case .none:
            return "Each agent and Worker shows in a plain terminal, without splits or extra windows."
        case .custom:
            return "Runs in a login shell. {session} is a name per agent or Worker, like echo-lanh-a3; {dir} is where it works; {command} shows it and must run in the first pane."
        }
    }

    private var isLookPreset: Bool { CustomLook.presets.contains(draft.look) }

    private var lookPresetBinding: Binding<String> {
        Binding {
            isLookPreset ? draft.look.name : "Custom"
        } set: { name in
            if let preset = CustomLook.presets.first(where: { $0.name == name }) {
                draft.look = preset
            }
        }
    }

    /// One part of the Custom look being edited; changing it makes the look custom, as with the
    /// terminal theme.
    private func lookBinding<Value>(_ key: WritableKeyPath<CustomLook, Value>) -> Binding<Value> {
        Binding {
            draft.look[keyPath: key]
        } set: { value in
            var look = draft.look
            look[keyPath: key] = value
            if CustomLook.presets.contains(where: { $0.name == look.name && $0 != look }) {
                look.name = "Custom"
            }
            draft.look = look
        }
    }

    private func lookColour(_ key: WritableKeyPath<CustomLook, String>) -> Binding<Color> {
        Binding {
            TerminalTheme.color(draft.look[keyPath: key])
        } set: { picked in
            guard let rgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
            lookBinding(key).wrappedValue = TerminalTheme.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        }
    }

    private var isPreset: Bool { TerminalTheme.presets.contains(model.appearance.theme) }

    /// A colour the terminal can also pick by itself: its well shows `auto`'s colour until one is
    /// picked, then Auto puts it back.
    private func optionalRow(_ title: String, _ key: WritableKeyPath<TerminalTheme, String?>,
                             auto: KeyPath<TerminalTheme, String>, note: String) -> some View {
        let theme = model.appearance.theme
        return SettingsRow(title) {
            HStack(spacing: 10) {
                SquareColorWell(selection: Binding {
                    TerminalTheme.color(theme[keyPath: key] ?? theme[keyPath: auto])
                } set: { picked in
                    guard let hex = Self.hex(picked) else { return }
                    edit { $0[keyPath: key] = hex }
                }, label: title)
                if theme[keyPath: key] != nil {
                    Button("Auto") { edit { $0[keyPath: key] = nil } }
                        .buttonStyle(.settings)
                }
            }
            if theme[keyPath: key] == nil { SettingsNote(note) }
        }
    }

    private func ansiColour(_ index: Int) -> Binding<Color> {
        Binding {
            TerminalTheme.color(model.appearance.theme.ansi[index])
        } set: { picked in
            guard let hex = Self.hex(picked) else { return }
            edit { $0.ansi[index] = hex }
        }
    }

    /// Changes the theme; a preset changed by hand becomes Custom.
    private func edit(_ change: (inout TerminalTheme) -> Void) {
        var theme = model.appearance.theme
        change(&theme)
        if TerminalTheme.presets.contains(where: { $0.name == theme.name && $0 != theme }) {
            theme.name = "Custom"
        }
        model.appearance.theme = theme
    }

    private static func hex(_ colour: Color) -> String? {
        guard let rgb = NSColor(colour).usingColorSpace(.sRGB) else { return nil }
        return TerminalTheme.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    private var presetBinding: Binding<String> {
        Binding {
            isPreset ? model.appearance.theme.name : "Custom"
        } set: { name in
            if let preset = TerminalTheme.presets.first(where: { $0.name == name }) {
                model.appearance.theme = preset
            }
        }
    }

    /// A theme colour as a SwiftUI colour; picking one makes the theme custom.
    private func colour(_ key: WritableKeyPath<TerminalTheme, String>) -> Binding<Color> {
        Binding {
            TerminalTheme.color(model.appearance.theme[keyPath: key])
        } set: { picked in
            guard let hex = Self.hex(picked) else { return }
            edit { $0[keyPath: key] = hex }
        }
    }
}

/// The 16 ANSI colours, normal over bright, each one a swatch that opens the colour panel.
struct Swatches: View {
    let theme: TerminalTheme
    let colour: (Int) -> Binding<Color>

    var body: some View {
        VStack(spacing: 3) {
            ForEach([0, 8], id: \.self) { start in
                HStack(spacing: 3) {
                    ForEach(start..<start + 8, id: \.self) { index in
                        SquareSwatch(selection: colour(index), label: TerminalTheme.ansiNames[index])
                    }
                }
            }
        }
        .padding(6)
        .background(TerminalTheme.color(theme.background))
        .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
    }
}

/// The Custom look while it is edited in Settings, before Apply.
final class LookDraft: ObservableObject {
    @Published var look = CustomLook.light
}

import AppKit
import HubCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings, one section each: the window's look, the terminal theme (a preset, then any colour changed
/// by hand), its background image, the font, the multiplexer agents run inside, what agents run
/// with, their Profiles, and the Orchestrator's rules, and Echo Remote.
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
                Section {
                    Picker("Appearance", selection: $model.windowLook) {
                        ForEach(WindowLook.allCases) { look in
                            Text(look.title).tag(look)
                        }
                    }
                    if model.windowLook == .matchTerminal {
                        Text(model.appearance.theme.isDark
                             ? "Dark, because the terminal theme is dark."
                             : "Light, because the terminal theme is light.")
                            .font(Ledger.font(11))
                            .foregroundStyle(.secondary)
                    }
                }
                if model.windowLook == .custom {
                    Section {
                        Picker("Preset", selection: lookPresetBinding) {
                            ForEach(CustomLook.presets) { look in
                                Text(look.name).tag(look.name)
                            }
                            if !isLookPreset {
                                Text("Custom").tag("Custom")
                            }
                        }
                        Picker("Mode", selection: lookBinding(\.dark)) {
                            Text("Light").tag(false)
                            Text("Dark").tag(true)
                        }
                        .pickerStyle(.segmented)
                        ColorPicker("Background", selection: lookColour(\.background), supportsOpacity: false)
                        ColorPicker("Surface", selection: lookColour(\.surface), supportsOpacity: false)
                        ColorPicker("Text", selection: lookColour(\.text), supportsOpacity: false)
                        ColorPicker("Accent", selection: lookColour(\.accent), supportsOpacity: false)
                        ColorPicker("Highlighter", selection: lookColour(\.highlighter), supportsOpacity: false)
                        Text("Lines, fields, and cards are mixed from these. Mode sets the system controls and the done, failed, and changed colours.")
                            .font(Ledger.font(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Section {
                        Button("Match the Terminal Theme (\(model.appearance.theme.name))") {
                            draft.look = CustomLook.from(model.appearance.theme)
                        }
                    }
                    Section {
                        HStack {
                            Text(draft.look == model.customLook ? "Applied." : "Not applied yet.")
                                .font(Ledger.font(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Revert") { draft.look = model.customLook }
                                .disabled(draft.look == model.customLook)
                            Button("Apply") { model.customLook = draft.look }
                                .keyboardShortcut(.defaultAction)
                                .disabled(draft.look == model.customLook)
                        }
                    }
                }
            }
            .onAppear { draft.look = model.customLook }
            case .theme:
            page {
                Section {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(TerminalTheme.presets) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                        if !isPreset {
                            Text("Custom").tag("Custom")
                        }
                    }
                    ColorPicker("Background", selection: colour(\.background), supportsOpacity: false)
                    ColorPicker("Text", selection: colour(\.foreground), supportsOpacity: false)
                    ColorPicker("Cursor", selection: colour(\.cursor), supportsOpacity: false)
                    ColorPicker("Selection", selection: colour(\.selection), supportsOpacity: false)
                    LabeledContent("Palette") { Swatches(theme: model.appearance.theme) }
                }
                Section {
                    Button("Match Orca (Ayu Dark, JetBrainsMono Nerd Font 14)") { model.appearance = .orca }
                }
            }
            case .background:
            page {
                Section {
                    LabeledContent("Image") {
                        HStack(spacing: 8) {
                            Text(model.appearance.backgroundImage.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…", action: chooseImage)
                            if model.appearance.backgroundImage != nil {
                                Button("Remove") { model.appearance.backgroundImage = nil }
                            }
                        }
                    }
                    // Always shown, so the controls can be found before an image is chosen.
                    Group {
                        LabeledContent {
                            HStack(spacing: 10) {
                                Slider(value: $model.appearance.backgroundImageDim, in: 0.3...0.95)
                                Text("\(Int((model.appearance.backgroundImageDim * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Dim")
                        }
                        LabeledContent {
                            HStack(spacing: 10) {
                                Slider(value: $model.appearance.backgroundImageBlur, in: 0...30)
                                Text("\(Int(model.appearance.backgroundImageBlur.rounded())) pt")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Blur")
                        }
                    }
                    .disabled(model.appearance.backgroundImage == nil)
                    if let path = model.appearance.backgroundImage {
                        if !FileManager.default.fileExists(atPath: path) {
                            Text("The image is gone; terminals show the theme background.")
                                .font(Ledger.font(11))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Choose an image to show behind every terminal. Text and coloured cells stay solid; dim or blur the image until the text reads easily.")
                        .font(Ledger.font(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            case .font:
            page {
                Section {
                    TextField("Family", text: $model.appearance.fontName)
                    Stepper(value: $model.appearance.fontSize, in: 9...28, step: 0.5) {
                        LabeledContent("Size", value: "\(model.appearance.fontSize.formatted()) pt")
                    }
                    if NSFont(name: model.appearance.fontName, size: 12) == nil {
                        Text("Not installed; the system monospaced font is used.")
                            .font(Ledger.font(11))
                            .foregroundStyle(.orange)
                    }
                }
            }
            case .multiplexer:
            page {
                Section {
                    Picker("Show agents and Workers inside", selection: $model.multiplexer.kind) {
                        ForEach(Multiplexer.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if model.multiplexer.kind == .custom {
                        TextField("Command", text: $model.multiplexer.command, axis: .vertical)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1...3)
                    } else if model.multiplexer.enabled {
                        LabeledContent("Command") {
                            Text(model.multiplexer.command)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Text(help)
                        .font(Ledger.font(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A change applies to terminals opened after it.")
                        .font(Ledger.font(11))
                        .foregroundStyle(.secondary)
                }
            }
            case .agents:
            page {
                AgentsSettings(agents: agents)
                OrchestratorSettings(agents: agents)
            }
            .onAppear(perform: refreshAgents)
            case .worktrees:
            page { WorktreeSettings() }
            case .memory:
            page { MemorySettings() }
            case .remote:
            page { RemoteSettings() }
        }
    }

    /// Profiles are the selected repo's, its own included.
    private func refreshAgents() {
        agents.repo = model.selectedRepo
        agents.refresh()
    }

    /// One section's page: its groups, scrolling when taller than the window.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
            guard let rgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
            var theme = model.appearance.theme
            theme[keyPath: key] = TerminalTheme.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            if TerminalTheme.presets.contains(where: { $0.name == theme.name && $0 != theme }) {
                theme.name = "Custom"
            }
            model.appearance.theme = theme
        }
    }
}

/// The 16 ANSI colours, normal over bright.
struct Swatches: View {
    let theme: TerminalTheme

    var body: some View {
        VStack(spacing: 3) {
            ForEach([0, 8], id: \.self) { start in
                HStack(spacing: 3) {
                    ForEach(start..<start + 8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TerminalTheme.color(theme.ansi[index]))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .padding(4)
        .background(TerminalTheme.color(theme.background), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The Custom look while it is edited in Settings, before Apply.
final class LookDraft: ObservableObject {
    @Published var look = CustomLook.light
}

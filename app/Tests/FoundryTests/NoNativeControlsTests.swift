import Foundation
import Testing

/// Echo draws every control with Foundry (ui-ux/0138): the app and Foundry itself never use the
/// system's controls, menus or alerts. The file chooser, the colour panel, tooltips and the menu
/// bar stay the system's, so they are not listed here.
private let banned: [(pattern: String, use: String)] = [
    (#"\bToggle\("#, "Checkbox"),
    (#"\.toggleStyle\("#, "Checkbox"),
    (#"\bPicker\("#, "SquarePicker"),
    (#"\.pickerStyle\("#, "SquarePicker"),
    (#"\bMenu\s*[({]"#, "MenuButton or foundryPopover with FoundryMenu"),
    (#"\.menuStyle\("#, "MenuButton"),
    (#"\.contextMenu\b"#, "foundryContextMenu"),
    (#"\bNSMenu\("#, "foundryContextMenu or foundryPointerMenu"),
    (#"\bNSMenuItem\("#, "FoundryMenuEntry"),
    (#"\bNSAlert\b"#, "FoundryAsk"),
    (#"\.confirmationDialog\("#, "FoundryAsk"),
    (#"\.alert\("#, "FoundryAsk"),
    (#"\.sheet\("#, "a Foundry modal"),
    (#"\.popover\("#, "foundryPopover"),
    (#"\bNSPopover\b"#, "foundryPopover"),
    (#"\bStepper\("#, "SquareStepper"),
    (#"\bSlider\("#, "SquareSlider"),
    (#"\bColorPicker\("#, "SquareColorWell"),
    (#"\bDisclosureGroup\b"#, "a Foundry row"),
    (#"\bProgressView\b"#, "Spinner"),
    (#"\bTabView\b"#, "LedgerSegmented"),
    (#"\bLink\("#, "a Button with .ledgerLink"),
    (#"\bForm\s*\{"#, "SettingsGroup and SettingsRow"),
    (#"\.searchable\("#, "a Foundry field"),
    (#"\busesFindBar\b"#, "FoundryFindBar"),
    (#"\bNS(PopUpButton|SegmentedControl|Slider|Stepper|SearchField|ComboBox|Switch|ProgressIndicator|DatePicker)\b"#, "a Foundry control"),
    (#"\bNSButton\("#, "a Foundry button"),
]

@Test func noViewUsesASystemControl() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")
    var found: [String] = []
    for folder in ["HubApp", "Foundry"] {
        let files = try FileManager.default.contentsOfDirectory(at: sources.appendingPathComponent(folder),
                                                                includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                for rule in banned where code.range(of: rule.pattern, options: .regularExpression) != nil {
                    found.append("\(folder)/\(file.lastPathComponent):\(number + 1): use \(rule.use): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }
    #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
}

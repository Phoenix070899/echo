import Foundry
import HubCore
import SwiftUI

extension SettingsLook {
    /// "06": a section's place in the list.
    static func number(_ section: SettingsSection) -> String {
        let at = (SettingsSection.allCases.firstIndex(of: section) ?? 0) + 1
        return at < 10 ? "0\(at)" : "\(at)"
    }
}

/// One section's page: its head and groups in a column at most 680 pt wide, centred in the sheet,
/// scrolling when taller than the window.
struct SettingsSheetPage<Content: View>: View {
    let section: SettingsSection
    var title: String?
    @ViewBuilder public var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                SettingsHead(label: "\(SettingsLook.number(section)) / \(section.title)", title: title ?? section.title)
                content()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 56)
            .frame(maxWidth: SettingsLook.column)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

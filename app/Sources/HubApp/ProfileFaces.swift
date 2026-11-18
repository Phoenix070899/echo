import AppKit
import Foundry
import HubCore
import SwiftUI

/// The faces a Profile can wear (ui-ux/0158): the pictures in Echo's `Faces/`, `r01c01.png` on,
/// read once and kept. A face the bundle does not have draws as none.
@MainActor
enum ProfileFaces {
    private static let folder = Bundle.main.resourceURL?.appendingPathComponent("Faces")
    private static var images: [String: NSImage] = [:]

    /// Every face Echo ships, in the sheet's order.
    static let names: [String] = {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return files.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
    }()

    static func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard names.contains(name), let folder,
              let image = NSImage(contentsOf: folder.appendingPathComponent(name + ".png")) else { return nil }
        images[name] = image
        return image
    }
}

/// A Profile's face, square in a hairline frame as Foundry draws pictures; an empty frame when it
/// has none, so the titles beside faces line up.
struct ProfileFace: View {
    let face: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = face.flatMap(ProfileFaces.image) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
        .accessibilityHidden(true)
    }
}

/// The Profile's face in its head, which opens the faces to pick from; read-only while the
/// Profile is Echo's own or an agent drafts it.
struct FacePicker: View {
    @Binding var face: String
    let enabled: Bool
    @StateObject private var shown = Flag()

    var body: some View {
        Button { shown.on.toggle() } label: {
            ProfileFace(face: face.isEmpty ? nil : face, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if enabled {
                        Image(systemName: "pencil")
                            .font(Ledger.font(10, .bold))
                            .foregroundStyle(Ledger.desk)
                            .frame(width: 18, height: 18)
                            .background(Ledger.ink)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Pick its face" : "Make your copy to change its face")
        .accessibilityLabel(face.isEmpty ? "Face: none" : "Face: \(face)")
        .foundryPopover(isPresented: $shown.on, width: FaceGrid.width) {
            FaceGrid(face: face) { picked in
                face = picked
                shown.on = false
            }
        }
    }
}

/// Every face in a grid, the picked one in the accent frame, then a foot to take the face off.
private struct FaceGrid: View {
    static let columns = 10
    static let cell: CGFloat = 40
    static let gap: CGFloat = 6
    static let width = CGFloat(columns) * cell + CGFloat(columns - 1) * gap + 28

    let face: String
    let pick: (String) -> Void

    var body: some View {
        FoundryPopover(label: "Faces") {
            FoundryPopoverHead(title: "Face", detail: "\(ProfileFaces.names.count) faces")
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.gap), count: Self.columns),
                          spacing: Self.gap) {
                    ForEach(ProfileFaces.names, id: \.self) { name in
                        FaceCell(name: name, picked: name == face) { pick(name) }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 360)
            .scrollIndicators(.never)
            FoundryPopoverFoot {
                Button("No face") { pick("") }
                    .buttonStyle(.ledgerLink)
                    .disabled(face.isEmpty)
            }
        }
    }
}

private struct FaceCell: View {
    let name: String
    let picked: Bool
    let pick: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: pick) {
            ProfileFace(face: name, size: FaceGrid.cell)
                .overlay(Rectangle().strokeBorder(picked || hover.on ? Ledger.accent : .clear,
                                                  lineWidth: Ledger.ruleStrong))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityLabel("Face \(name)")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

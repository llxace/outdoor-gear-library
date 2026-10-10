import SwiftUI
import AppKit

struct GearPhoto: View {
    @EnvironmentObject var store: GearStore
    let filename: String?
    @State private var image: NSImage?
    @State private var expanded = false
    @State private var hoverTask: Task<Void, Never>?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    GearDesign.accent.opacity(0.08)
                    Image(systemName: "backpack").foregroundStyle(GearDesign.accent)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { inside in
                hoverTask?.cancel()
                if inside && image != nil {
                    hoverTask = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                        guard !Task.isCancelled else { return }
                        expanded = true
                    }
                } else {
                    expanded = false
                }
            }
            .popover(isPresented: $expanded, arrowEdge: .trailing) {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 400, height: 400)
                        .padding(12).background(Color.white).accessibilityLabel("装备照片大图")
                }
            }
            .accessibilityAction(named: Text("查看大图")) { if image != nil { expanded = true } }
            .onDisappear {
                hoverTask?.cancel()
                expanded = false
            }
            .task(id: filename) {
                hoverTask?.cancel()
                expanded = false
                image = nil
                guard let filename else { return }
                let url = store.photoURL(filename)
                let data = await Task.detached { try? LocalAssetFiles.imageData(at: url) }.value
                guard !Task.isCancelled else { return }
                image = data.flatMap { NSImage(data: $0) }
            }
    }
}

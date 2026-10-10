import SwiftUI

struct GearTrashView: View {
    @EnvironmentObject private var library: GearLibrary
    @State private var deleting: Gear?

    private var trashed: [Gear] { library.gears.filter(\.trashed) }

    var body: some View {
        List {
            if trashed.isEmpty {
                ContentUnavailableView("回收站是空的", systemImage: "trash", description: Text("从装备库移除的装备会出现在这里。"))
            } else {
                ForEach(trashed) { gear in
                    HStack {
                        GearRow(gear: gear)
                        Spacer()
                        Button("恢复") { library.restore(gear) }.buttonStyle(.bordered)
                    }
                    .swipeActions {
                        Button("彻底删除", systemImage: "trash.fill", role: .destructive) { deleting = gear }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(OutdoorPalette.background)
        .navigationTitle("回收站 · \(trashed.count)")
        .confirmationDialog("彻底删除这件装备？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("彻底删除", role: .destructive) {
                    if let deleting { library.deletePermanently(deleting) }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: {
                Text("它会从装备清单和打包清单中移除。")
            }
    }
}

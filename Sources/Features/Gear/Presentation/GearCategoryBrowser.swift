import SwiftUI
import AppKit

struct GearCategoryBrowser: View {
    @EnvironmentObject var store: GearStore
    @Binding var selection: String
    var showPackingSelection = false
    private func row(_ name: String, path: String) -> some View {
        let contents = store.items.filter { store.inventory.matchesCategoryFolder($0, path: path) }
        let selected = contents.filter { store.inventory.packingQuantity($0.id) != nil }.count
        return HStack(spacing: 10) {
            GearCategoryIcon(name: name).font(.title2).foregroundStyle(GearDesign.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.medium))
                Text("\(contents.count) 项" + (showPackingSelection && selected > 0 ? " · 已选 \(selected)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 7)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("装备分类").font(.headline).padding(.horizontal, 12).padding(.top, 12)
            List(selection: $selection) {
                row("全部装备", path: "全部分类").tag("全部分类")
                categoryFolders
                row("已损坏", path: "已损坏").tag("已损坏")
            }.listStyle(.plain).scrollContentBackground(.hidden).background(GearDesign.surface)
                .accessibilityLabel("装备分类文件夹")
        }
    }

    private var categoryFolders: some View {
        ForEach(store.inventory.categories, id: \.self) { parent in
            let children = GearSubcategories.children(of: parent)
            if children.isEmpty {
                row(parent, path: parent).tag(parent)
            } else {
                DisclosureGroup {
                    ForEach(children, id: \.self) { child in
                        row(child, path: parent + "/" + child).tag(parent + "/" + child)
                    }
                } label: {
                    row(parent, path: parent)
                }.tag(parent)
            }
        }
    }
}

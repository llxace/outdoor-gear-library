import SwiftUI

struct HistoricalEquipmentEditor: View {
    @Binding var items: [HikeGear]
    @State private var search = ""
    @State private var category: String?
    private var visibleIDs: Set<UUID> {
        Set(items.filter { HistoryEquipment.matches($0.gear, search: search, category: category) }.map(\.id))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("搜索当次装备", text: $search).textFieldStyle(.roundedBorder)
                Picker("分类", selection: $category) {
                    Text("全部分类").tag(nil as String?)
                    ForEach(HistoryEquipment.categories(items.map(\.gear)), id: \.self) { Text($0).tag(Optional($0)) }
                }.frame(width: 220)
            }
            Text("\(items.count) 项 · 点击展开可填写当时的详细资料和使用感受").font(.caption).foregroundStyle(.secondary)
            ForEach($items) { $item in
                if visibleIDs.contains(item.id) {
                    HistoricalEquipmentRow(item: $item) { items.removeAll { $0.id == item.id } }
                }
            }
            if items.isEmpty {
                Text("还没有当次装备，请从装备库选择或手动补充。").foregroundStyle(.secondary)
            } else if visibleIDs.isEmpty {
                Text("没有符合条件的历史装备。").foregroundStyle(.secondary)
            }
        }
        .onChange(of: items.map { HistoryEquipment.category($0.gear) }) { _, categories in
            if let category, !categories.contains(category) { self.category = nil }
        }
    }
}

private struct HistoricalEquipmentRow: View {
    @Binding var item: HikeGear
    let remove: () -> Void
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("分类", text: $item.gear.category)
                    TextField("品牌", text: $item.gear.brand)
                    TextField("型号", text: $item.gear.model)
                }.textFieldStyle(.roundedBorder)
                TextField("当次使用感受、问题或下次调整", text: $item.gear.notes, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                Text("这些修改仅保存在本次历史记录中。").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                GearPhoto(filename: item.gear.photo).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("装备名称", text: $item.gear.name).textFieldStyle(.roundedBorder)
                    Text(HistoryEquipment.category(item.gear) + (item.ownerName.map { " · 来自 " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack {
                    Text("单件 g").font(.caption).foregroundStyle(.secondary)
                    TextField("重量", value: $item.gear.weight, format: .number).frame(width: 75)
                }
                VStack {
                    Text("携带数量").font(.caption).foregroundStyle(.secondary)
                    TextField("数量", value: $item.quantity, format: .number).frame(width: 60)
                }
                Text((item.gear.weight * item.quantity).formatted() + " g").monospacedDigit().frame(
                    width: 85, alignment: .trailing)
                Button(action: remove) { Image(systemName: "minus.circle") }.help("从历史清单移除")
            }.textFieldStyle(.roundedBorder)
        }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

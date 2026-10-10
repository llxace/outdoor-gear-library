import SwiftUI

struct HistoricalEquipmentSummary: View {
    let items: [HikeGear]
    @State private var search = ""
    @State private var category = "全部分类"
    @State private var expanded: Set<UUID> = []
    private var visible: [HikeGear] {
        items.filter { HistoryEquipment.matches($0.gear, search: search, category: category == "全部分类" ? nil : category) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("搜索当次装备、品牌或备注", text: $search).textFieldStyle(.roundedBorder)
                Picker("分类", selection: $category) {
                    Text("全部分类").tag("全部分类")
                    ForEach(HistoryEquipment.categories(items.map(\.gear)), id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 180)
            }
            ForEach(HistoryEquipment.categories(visible.map(\.gear)), id: \.self) { categorySection($0) }
            if visible.isEmpty { Text("没有符合条件的装备。").foregroundStyle(.secondary) }
        }
    }

    private func categorySection(_ category: String) -> some View {
        let group = visible.filter { HistoryEquipment.category($0.gear) == category }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(group.count) 项 · \(HistoryEquipment.weight(group).formatted()) g")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }.padding(.horizontal, 4)
            ForEach(group) { item in
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow(item)
                    if expanded.contains(item.id) {
                        let details = [item.gear.brand, item.gear.model].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !details.isEmpty { Text(details).font(.callout).textSelection(.enabled) }
                        if !item.gear.notes.isEmpty {
                            Text("备注").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(item.gear.notes).font(.callout).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }.padding(12).background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func summaryRow(_ item: HikeGear) -> some View {
        HStack(alignment: .center, spacing: 12) {
            GearPhoto(filename: item.gear.photo).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.gear.name).fontWeight(.medium).lineLimit(2)
                let details = [item.gear.brand, item.gear.model].filter { !$0.isEmpty }.joined(separator: " · ")
                if !details.isEmpty { Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let owner = item.ownerName { Text("来自 " + owner).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text((item.gear.weight * item.quantity).formatted() + " g").fontWeight(.medium).monospacedDigit()
                Text("\(item.quantity.formatted()) × \(item.gear.weight.formatted()) g").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
            } label: { Image(systemName: expanded.contains(item.id) ? "chevron.up" : "chevron.down").frame(width: 22, height: 24) }
                .buttonStyle(.borderless).foregroundStyle(HikeStyle.accent)
                .accessibilityLabel((expanded.contains(item.id) ? "收起" : "展开") + item.gear.name + "的详细资料")
        }
    }
}

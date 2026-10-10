import SwiftUI

struct HistoricalGearPicker: View {
    @Environment(\.dismiss) private var dismiss
    let items: [Gear]
    let existing: [HikeGear]
    let add: ([HikeGear]) -> Void
    @State private var search = ""
    @State private var category: String?
    @State private var selected: Set<UUID> = []
    private var visible: [Gear] {
        items.filter { HistoryEquipment.matches($0, search: search, category: category) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var existingIDs: Set<UUID> {
        Set(existing.filter { $0.ownerName == nil }.map { $0.gear.id })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从装备库补充历史装备").font(.title2.bold())
            Text("选择当时携带的装备，添加后可填写实际数量和当时重量。").foregroundStyle(.secondary)
            TextField("搜索名称、品牌、型号、标签或备注", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Picker("分类", selection: $category) {
                    Text("全部分类").tag(nil as String?)
                    ForEach(HistoryEquipment.categories(items), id: \.self) { Text($0).tag(Optional($0)) }
                }
                Text("已选 \(selected.count) 项").foregroundStyle(.secondary)
                Button("选择筛选结果") { selected.formUnion(visible.map(\.id).filter { !existingIDs.contains($0) }) }
                Button("清空选择") { selected.removeAll() }.disabled(selected.isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visible) { gear in pickerRow(gear) }
                    if visible.isEmpty { Text("没有符合条件的装备").foregroundStyle(.secondary).padding(30) }
                }
            }
            HStack {
                Text("已记录的装备不会重复添加。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("添加 \(selected.count) 项") { addSelection() }
                    .buttonStyle(.borderedProminent).disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 740, height: 540)
    }

    private func pickerRow(_ gear: Gear) -> some View {
        HStack(spacing: 12) {
            Toggle(gear.name, isOn: selection(gear.id)).labelsHidden().disabled(existingIDs.contains(gear.id))
            GearPhoto(filename: gear.photo).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(gear.name).font(.headline)
                Text(
                    [HistoryEquipment.category(gear), gear.brand, gear.model].filter { !$0.isEmpty }.joined(
                        separator: " · ")
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(gear.weight == 0 ? "重量待补" : "\(gear.weight.formatted()) g / 件").monospacedDigit()
            if existingIDs.contains(gear.id) { Text("已记录").foregroundStyle(.secondary) }
        }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func selection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { value in
                if value { selected.insert(id) } else { selected.remove(id) }
            })
    }

    private func addSelection() {
        let additions = items.filter { selected.contains($0.id) && !existingIDs.contains($0.id) }
            .map { HikeGear(gear: $0, quantity: 1) }
        add(additions)
        dismiss()
    }
}

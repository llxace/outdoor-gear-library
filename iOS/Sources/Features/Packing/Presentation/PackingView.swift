import SwiftUI

struct PackingView: View {
    @EnvironmentObject private var library: GearLibrary
    @State private var search = ""
    @State private var addingCompanionGear = false
    @State private var confirmingClear = false

    private var availableGear: [Gear] {
        library.activeGear.filter { gear in
            gear.status != "损坏" && (search.isEmpty ||
                [gear.name, gear.brand, gear.model, gear.category].joined(separator: " ")
                    .localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RouteWeatherCard().environmentObject(library).listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear).padding(.vertical, 4)
                }
                Section {
                    summary
                }
                if !library.packingItems.isEmpty || !library.borrowedPackingItems.isEmpty {
                    Section("本次携带 · \(library.packedGear.count + library.borrowedPackingItems.filter { !$0.unavailable }.count) 项") {
                        ForEach(library.packedGear) { gear in
                            PackingGearRow(gear: gear, quantity: library.packingQuantity(for: gear.id) ?? 1,
                                           update: { library.setPackingQuantity($0, for: gear.id) })
                        }
                        ForEach(library.borrowedPackingItems) { item in
                            BorrowedPackingRow(item: item,
                                               update: { library.updateBorrowedQuantity($0, for: item.id) },
                                               remove: { library.removeBorrowedGear(item.id) })
                        }
                    }
                }
                Section {
                    Button { addingCompanionGear = true } label: {
                        Label("添加别人的装备", systemImage: "person.2.badge.plus")
                    }
                    .listRowBackground(OutdoorPalette.glassTint)
                }
                Section("从我的装备库添加") {
                    ForEach(availableGear) { gear in
                        Button { library.setPackingQuantity(min(1, gear.quantity), for: gear.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: library.packedIDs.contains(gear.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(library.packedIDs.contains(gear.id) ? OutdoorPalette.accent : .secondary)
                                GearRow(gear: gear)
                            }
                        }.buttonStyle(.plain).disabled(library.packedIDs.contains(gear.id))
                    }
                    if availableGear.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OutdoorPalette.background)
            .searchable(text: $search, prompt: "搜索装备名称、品牌或型号")
            .navigationTitle("打包")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", systemImage: "eraser") { confirmingClear = true }
                        .disabled(library.packingItems.isEmpty && library.borrowedPackingItems.isEmpty)
                }
            }
            .sheet(isPresented: $addingCompanionGear) {
                BorrowedGearPicker().environmentObject(library)
            }
            .confirmationDialog("清空本次打包清单？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清空清单", role: .destructive) { library.clearPacking() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("自己的装备和同行者装备都会从本次清单移除。")
            }
            .alert("户外装备库", isPresented: Binding(
                get: { library.alert != nil }, set: { if !$0 { library.alert = nil } })) {
                    Button("好", role: .cancel) { library.alert = nil }
                } message: { Text(library.alert ?? "") }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("总重量").foregroundStyle(.secondary)
                Spacer()
                Text("\((library.packedWeight / 1000).formatted(.number.precision(.fractionLength(3)))) kg")
                    .font(.title2.bold().monospacedDigit())
            }
            HStack {
                Text("装备价值").foregroundStyle(.secondary)
                Spacer()
                Text(library.packedValue.formatted(.currency(code: "CNY"))).font(.headline)
            }
            if library.missingPackingWeightCount > 0 {
                Label("\(library.missingPackingWeightCount) 项装备未填写重量", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(OutdoorPalette.warm)
            }
            if library.unavailablePackingCount > 0 {
                Label("\(library.unavailablePackingCount) 项打包资料当前不可用", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }.padding(.vertical, 4)
    }
}

private struct PackingGearRow: View {
    let gear: Gear
    let quantity: Double
    let update: (Double?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gear.name).font(.headline)
                Text("\(gear.category) · \(gear.weight.formatted()) g/件 · 库存 \(gear.quantity.formatted())")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("携带价值 \((gear.purchasePrice / max(gear.quantity, 1) * quantity).formatted(.currency(code: "CNY")))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            quantityControl(quantity: quantity, maximum: gear.quantity) { next in update(next == 0 ? nil : next) }
        }.padding(.vertical, 4)
    }
}

private struct BorrowedPackingRow: View {
    let item: BorrowedPackingEntry
    let update: (Double) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.gear.name).font(.headline)
                Text("\(item.ownerName) 的装备 · \(item.gear.weight.formatted()) g/件")
                    .font(.caption).foregroundStyle(.secondary)
                Text("携带价值 \((item.gear.purchasePrice / max(item.gear.quantity, 1) * item.quantity).formatted(.currency(code: "CNY")))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            quantityControl(quantity: item.quantity, maximum: item.gear.quantity) { next in
                if next == 0 { remove() } else { update(next) }
            }
        }.padding(.vertical, 4)
    }
}

@ViewBuilder
private func quantityControl(quantity: Double, maximum: Double, update: @escaping (Double) -> Void) -> some View {
    HStack(spacing: 5) {
        Button { update(max(0, quantity - 1)) } label: { Image(systemName: "minus") }
            .buttonStyle(.bordered).controlSize(.small)
        Text(quantity.formatted()).font(.caption.monospacedDigit()).frame(minWidth: 28)
        Button { update(min(maximum, quantity + 1)) } label: { Image(systemName: "plus") }
            .buttonStyle(.bordered).controlSize(.small).disabled(quantity >= maximum)
    }
}

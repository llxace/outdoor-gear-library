import SwiftUI

struct PackingListView: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @State private var search = ""
    @State private var packingSection = "装备"
    @State private var category = "全部分类"
    @State private var selectedOnly = false
    @State private var addingOthers = false
    @State private var cleared: [PackingItem]?
    @State private var clearedBorrowed: [BorrowedPackingItem] = []
    private var candidates: [Gear] {
        store.items.filter { gear in
            store.inventory.matchesCategoryFolder(gear, path: category)
                && (!selectedOnly || store.inventory.packingQuantity(gear.id) != nil)
                && (search.isEmpty
                    || [gear.name, gear.brand, gear.model].joined(separator: " ").localizedCaseInsensitiveContains(
                        search))
        }.sorted {
            let firstFavorite = store.inventory.isFavorite($0.id)
            let secondFavorite = store.inventory.isFavorite($1.id)
            if firstFavorite != secondFavorite { return firstFavorite }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var borrowed: [BorrowedPackingItem] {
        store.inventory.borrowedPackingItems.filter { item in
            matchesBorrowedFolder(item)
                && (search.isEmpty
                    || [item.gear.name, item.gear.brand, item.gear.model, item.ownerName].joined(separator: " ")
                        .localizedCaseInsensitiveContains(search))
        }
    }
    private func matchesBorrowedFolder(_ item: BorrowedPackingItem) -> Bool {
        guard category != "全部分类" else { return true }
        if category == "已损坏" { return item.gear.status == "损坏" }
        let parts = category.split(separator: "/").map(String.init)
        guard parts.first == item.gear.category else { return false }
        return parts.count == 1 || parts[1] == GearSubcategories.resolved(for: item.gear, stored: item.subcategory)
    }
    private var folderName: String { category == "全部分类" ? "全部装备" : String(category.split(separator: "/").last ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            packingHeading
            VSplitView {
                GeometryReader { area in
                    ScrollView {
                        PackingTripHeader(availableHeight: area.size.height, availableWidth: area.size.width)
                            .frame(minHeight: area.size.height, alignment: .top)
                    }
                }.frame(minHeight: 150, idealHeight: 210, maxHeight: 450)
                VStack(alignment: .leading, spacing: 8) {
                    packingSummary
                    HStack {
                        Picker("打包内容", selection: $packingSection) {
                            Text("装备清单").tag("装备")
                            Text("路餐与饮水").tag("路餐")
                        }.pickerStyle(.segmented).frame(width: 270)
                        Spacer()
                        Text(
                            "装备 " + store.inventory.packingWeight.formatted() + " g · 路餐与水 "
                                + store.inventory.mealPlan.totalWeight.formatted() + " g"
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    if packingSection == "路餐" {
                        TrailMealsView().frame(maxHeight: .infinity)
                    } else {
                        equipmentBrowser
                    }
                }.frame(minHeight: 230)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(GearDesign.background)
            .disabled(!store.ready)
            .sheet(isPresented: $addingOthers) {
                BorrowedGearPicker().environmentObject(store).environmentObject(libraries)
            }
            .onAppear { libraries.refreshBorrowedPackingItems() }
    }

    private var packingHeading: some View {
        HStack {
            Text("打包").font(.title.bold())
            Spacer()
            Button("添加别人的装备", systemImage: "person.2.badge.plus") { addingOthers = true }
                .disabled(libraries.users.count < 2)
            Picker("用户装备库", selection: Binding(get: { libraries.selectedID }, set: { _ = libraries.select($0) })) {
                ForEach(libraries.users) { Text($0.name).tag($0.id) }
            }.frame(maxWidth: 270)
        }
    }

    private var packingTotals: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Label("装备清单", systemImage: "list.bullet.clipboard").font(.headline)
            Text(
                store.inventory.missingPackingWeights == 0 && store.inventory.unavailablePackingItems == 0
                    ? "总重量" : "已知重量"
            ).foregroundStyle(.secondary)
            Text(
                ((store.inventory.packingWeight + store.inventory.mealPlan.totalWeight) / 1000).formatted(
                    .number.precision(.fractionLength(3))) + " kg"
            )
            .font(.title.bold()).monospacedDigit()
            Text(
                (store.inventory.packingWeight + store.inventory.mealPlan.totalWeight).formatted(
                    .number.precision(.fractionLength(0...2))) + " g"
            )
            .foregroundStyle(.secondary).monospacedDigit()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.inventory.missingPackingPrices == 0 ? "装备价值" : "已知装备价值").foregroundStyle(.secondary)
                Text(store.money(store.inventory.packingValue))
                    .font(.title3.bold()).monospacedDigit()
            }.help("按录入购买总价 ÷ 库内数量 × 携带数量计算，包含借用装备；未填价格的装备不计入。")
            Spacer()
            Text("已选 \(store.inventory.packingCount) 项装备").foregroundStyle(.secondary)
            Button("一键清空", systemImage: "eraser") {
                let own = store.inventory.packingItems
                let others = store.inventory.borrowedPackingItems
                if store.clearPackingList() {
                    cleared = own
                    clearedBorrowed = others
                }
            }.disabled(store.inventory.packingItems.isEmpty && store.inventory.borrowedPackingItems.isEmpty)
            if let cleared {
                Button("撤销清空") {
                    if store.restoreClearedPacking(own: cleared, borrowed: clearedBorrowed) {
                        self.cleared = nil
                        libraries.refreshBorrowedPackingItems()
                    }
                }
            }
        }
    }

    private var equipmentSearch: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("在当前分类中搜索名称、品牌或型号", text: $search).textFieldStyle(.plain)
            }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35)))
            Toggle("只看已选", isOn: $selectedOnly)
        }
    }

    private var borrowedEquipmentSection: some View {
        Section("别人的装备") {
            ForEach(borrowed) { item in
                HStack(spacing: 12) {
                    GearPhoto(filename: item.gear.photo).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.gear.name).fontWeight(.medium)
                        Text(
                            "来自 " + item.ownerName + " · 库内 \(item.gear.quantity.formatted()) 件"
                                + (item.unavailable ? " · 来源不可用，未计入重量" : "")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PackingQuantityControl(name: item.gear.name, quantity: item.quantity, maximum: item.gear.quantity) {
                        _ = store.setBorrowedQuantity($0, item: item)
                    }.disabled(item.unavailable)
                    Text(item.unavailable ? "—" : (item.gear.weight * item.quantity).formatted() + " g").frame(
                        width: 110, alignment: .trailing)
                    Button {
                        _ = store.setBorrowedQuantity(nil, item: item)
                    } label: {
                        Image(systemName: "xmark")
                    }.help("移除这项借用装备")
                }.padding(.vertical, 6)
            }
        }
    }

    private var ownedEquipmentRows: some View {
        ForEach(candidates) { ownedEquipmentRow(for: $0) }
    }

    private func ownedEquipmentRow(for gear: Gear) -> some View {
        let quantity = store.inventory.packingQuantity(gear.id)
        let damaged = gear.status == "损坏"
        let weight = gear.weight > 0 ? gear.weight.formatted() + " g / 件" : "未填重量"
        let details = "\(gear.category) · \(weight) · 库内 \(gear.quantity.formatted()) 件"
            + (damaged ? " · 已损坏，无法装包" : "")
        let packedWeight = quantity.map { gear.weight > 0 ? (gear.weight * $0).formatted() + " g" : "待补重量" } ?? "—"

        return HStack(spacing: 16) {
            Toggle(
                isOn: Binding(
                    get: { store.inventory.packingQuantity(gear.id) != nil },
                    set: { checked in
                        _ = store.setPackingQuantity(checked ? min(1, gear.quantity) : nil, for: gear.id)
                    })
            ) {
                HStack(spacing: 12) {
                    GearPhoto(filename: gear.photo).frame(width: 44, height: 44)
                        .accessibilityLabel(gear.name + "的照片")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gear.name).fontWeight(.medium)
                        Text(details).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.toggleStyle(.checkbox).disabled(damaged)
            Spacer()
            PackingQuantityControl(name: gear.name, quantity: quantity, maximum: gear.quantity) {
                _ = store.setPackingQuantity($0, for: gear.id)
            }
            .disabled(damaged)
            Text(damaged ? "已损坏" : packedWeight)
                .monospacedDigit().frame(width: 110, alignment: .trailing)
        }.padding(.vertical, 6).opacity(damaged ? 0.45 : 1)
    }

    private var packingSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            packingTotals
            if store.inventory.missingPackingWeights > 0 {
                Label("\(store.inventory.missingPackingWeights) 项未填重量，请在装备库补齐", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if store.inventory.unavailablePackingItems > 0 {
                HStack {
                    Text("\(store.inventory.unavailablePackingItems) 项已移出装备库，未计入重量").foregroundStyle(.secondary)
                    Button("从清单移除") { store.removeUnavailablePackingItems() }
                }
            }
        }.padding(8).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var equipmentBrowser: some View {
        HSplitView {
            GearCategoryBrowser(selection: $category, showPackingSelection: true)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 270)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label {
                        Text(folderName)
                    } icon: {
                        GearCategoryIcon(name: folderName)
                    }
                    .font(.title3.bold())
                    Spacer()
                    Text("\(candidates.count + borrowed.count) 项装备").font(.callout).foregroundStyle(.secondary)
                }
                equipmentSearch
                HStack {
                    Text("装备名称")
                    Spacer()
                    Text("携带数量").frame(width: 150)
                    Text("小计").frame(width: 110, alignment: .trailing)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                List {
                    if !borrowed.isEmpty {
                        borrowedEquipmentSection
                    }
                    ownedEquipmentRows
                }.overlay {
                    if candidates.isEmpty && borrowed.isEmpty {
                        Text(store.items.isEmpty ? "装备库暂无装备，请先在装备库录入" : "暂无符合条件的装备").foregroundStyle(.secondary)
                    }
                }
            }.padding(12).frame(minWidth: 500)
        }.frame(maxHeight: .infinity).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
            .onChange(of: category) { _ in search = "" }
    }
}

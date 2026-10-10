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
    private func matchesBorrowedFolder(_ item: BorrowedPackingItem, path: String? = nil) -> Bool {
        let selectedCategory = path ?? category
        guard selectedCategory != "全部分类" else { return true }
        if selectedCategory == "已损坏" { return item.gear.status == "损坏" }
        let parts = selectedCategory.split(separator: "/").map(String.init)
        guard parts.first == item.gear.category else { return false }
        return parts.count == 1 || parts[1] == GearSubcategories.resolved(for: item.gear, stored: item.subcategory)
    }
    private var folderName: String { category == "全部分类" ? "全部装备" : String(category.split(separator: "/").last ?? "") }
    private var categoryOptions: [(title: String, path: String)] {
        [(title: "全部装备", path: "全部分类")]
            + store.inventory.categories.map { (title: $0, path: $0) }
            + [(title: "已损坏", path: "已损坏")]
    }
    var body: some View {
        GeometryReader { viewport in
            let wide = viewport.size.width >= 820 && viewport.size.width > viewport.size.height * 1.1
            VStack(alignment: .leading, spacing: 12) {
                packingHeading
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        tripColumn(width: min(440, viewport.size.width * 0.38), height: viewport.size.height - 76)
                            .frame(width: min(440, viewport.size.width * 0.38))
                        packingWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        tripColumn(width: viewport.size.width - 32, height: viewport.size.width >= 760 ? 310 : 500)
                            .frame(height: viewport.size.width >= 760 ? 310 : 500)
                        packingWorkspace.frame(maxHeight: .infinity)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GearDesign.background)
        }
            .disabled(!store.ready)
            .sheet(isPresented: $addingOthers) {
                BorrowedGearPicker().environmentObject(store).environmentObject(libraries)
            }
            .onAppear { libraries.refreshBorrowedPackingItems() }
    }

    private func tripColumn(width: CGFloat, height: CGFloat) -> some View {
        ScrollView {
            PackingTripHeader(availableHeight: height, availableWidth: width)
        }
        .scrollIndicators(.hidden)
        .background(GearDesign.background)
    }

    private var packingWorkspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            packingSummary
            HStack(spacing: 12) {
                Picker("打包内容", selection: $packingSection) {
                    Text("装备清单").tag("装备")
                    Text("路餐与饮水").tag("路餐")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer(minLength: 8)
                Text("装备 \(store.inventory.packingWeight.formatted()) g · 路餐与水 \(store.inventory.mealPlan.totalWeight.formatted()) g")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if packingSection == "路餐" {
                TrailMealsView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                equipmentBrowser
            }
        }
        .frame(minHeight: 230, maxHeight: .infinity, alignment: .topLeading)
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
            clearPackingButton
            if let cleared { undoClearButton(cleared) }
        }
    }

    private var equipmentSearch: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("在当前分类中搜索名称、品牌或型号", text: $search).textFieldStyle(.plain)
            }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35)))
                .layoutPriority(1)
            Toggle("只看已选", isOn: $selectedOnly).fixedSize()
        }
    }

    private func borrowedEquipmentSection(compact: Bool) -> some View {
        Section("别人的装备") {
            ForEach(borrowed) { item in
                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: 8) {
                            borrowedGearLabel(item)
                            HStack {
                                borrowedQuantityControl(item)
                                Spacer(minLength: 8)
                                borrowedSubtotal(item)
                                removeBorrowedButton(item)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            borrowedGearLabel(item)
                            Spacer()
                            borrowedQuantityControl(item)
                            borrowedSubtotal(item).frame(width: 110, alignment: .trailing)
                            removeBorrowedButton(item)
                        }
                    }
                }.padding(.vertical, 6).listRowBackground(GearDesign.surface)
            }
        }
    }

    private func borrowedGearLabel(_ item: BorrowedPackingItem) -> some View {
        HStack(spacing: 12) {
            GearPhoto(filename: item.gear.photo).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.gear.name).fontWeight(.medium).lineLimit(2)
                Text(
                    "来自 " + item.ownerName + " · 库内 \(item.gear.quantity.formatted()) 件"
                        + (item.unavailable ? " · 来源不可用，未计入重量" : "")
                ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func borrowedQuantityControl(_ item: BorrowedPackingItem) -> some View {
        PackingQuantityControl(name: item.gear.name, quantity: item.quantity, maximum: item.gear.quantity) {
            _ = store.setBorrowedQuantity($0, item: item)
        }.disabled(item.unavailable)
    }

    private func borrowedSubtotal(_ item: BorrowedPackingItem) -> some View {
        Text(item.unavailable ? "—" : (item.gear.weight * item.quantity).formatted() + " g")
            .monospacedDigit()
    }

    private func removeBorrowedButton(_ item: BorrowedPackingItem) -> some View {
        Button {
            _ = store.setBorrowedQuantity(nil, item: item)
        } label: {
            Image(systemName: "xmark")
        }.help("移除这项借用装备")
    }

    private func ownedEquipmentRows(compact: Bool) -> some View {
        ForEach(candidates) { gear in
            let quantity = store.inventory.packingQuantity(gear.id)
            let damaged = gear.status == "损坏"
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        gearSelectionToggle(gear, damaged: damaged)
                        HStack {
                            PackingQuantityControl(name: gear.name, quantity: quantity, maximum: gear.quantity) {
                                _ = store.setPackingQuantity($0, for: gear.id)
                            }.disabled(damaged)
                            Spacer(minLength: 8)
                            ownedSubtotal(gear, quantity: quantity, damaged: damaged)
                        }
                    }
                } else {
                    HStack(spacing: 16) {
                        gearSelectionToggle(gear, damaged: damaged)
                        Spacer()
                        PackingQuantityControl(name: gear.name, quantity: quantity, maximum: gear.quantity) {
                            _ = store.setPackingQuantity($0, for: gear.id)
                        }.disabled(damaged)
                        ownedSubtotal(gear, quantity: quantity, damaged: damaged).frame(width: 110, alignment: .trailing)
                    }
                }
            }.padding(.vertical, 6).opacity(damaged ? 0.45 : 1).listRowBackground(GearDesign.surface)
        }
    }

    private func gearSelectionToggle(_ gear: Gear, damaged: Bool) -> some View {
        let weight = gear.weight > 0 ? gear.weight.formatted() + " g / 件" : "未填重量"
        let details = gear.category + " · " + weight + " · 库内 " + gear.quantity.formatted() + " 件"
            + (damaged ? " · 已损坏，无法装包" : "")
        return Toggle(isOn: packingSelection(for: gear)) {
            gearSelectionLabel(gear, details: details)
        }
        .toggleStyle(.switch).disabled(damaged)
    }

    private func packingSelection(for gear: Gear) -> Binding<Bool> {
        Binding(
            get: { store.inventory.packingQuantity(gear.id) != nil },
            set: { checked in
                _ = store.setPackingQuantity(checked ? min(1, gear.quantity) : nil, for: gear.id)
            })
    }

    private func gearSelectionLabel(_ gear: Gear, details: String) -> some View {
        HStack(spacing: 12) {
            GearPhoto(filename: gear.photo).frame(width: 44, height: 44)
                .accessibilityLabel(gear.name + "的照片")
            VStack(alignment: .leading, spacing: 4) {
                Text(gear.name).fontWeight(.medium).lineLimit(2)
                Text(details).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ownedSubtotal(_ gear: Gear, quantity: Double?, damaged: Bool) -> some View {
        Text(
            damaged
                ? "已损坏"
                : (quantity.map { gear.weight > 0 ? (gear.weight * $0).formatted() + " g" : "待补重量" } ?? "—")
        ).monospacedDigit()
    }

    private var packingSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                packingTotals.fixedSize(horizontal: true, vertical: false)
                compactPackingTotals
            }
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

    private var compactPackingTotals: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("装备清单", systemImage: "list.bullet.clipboard").font(.headline)
                Spacer(minLength: 8)
                Text(((store.inventory.packingWeight + store.inventory.mealPlan.totalWeight) / 1000).formatted(
                    .number.precision(.fractionLength(3))) + " kg").font(.title3.bold()).monospacedDigit()
            }
            HStack {
                Text(store.inventory.missingPackingPrices == 0 ? "装备价值" : "已知装备价值").foregroundStyle(.secondary)
                Text(store.money(store.inventory.packingValue)).fontWeight(.semibold).monospacedDigit()
                Spacer(minLength: 8)
                Text("已选 \(store.inventory.packingCount) 项").foregroundStyle(.secondary)
            }
            HStack {
                Text((store.inventory.packingWeight + store.inventory.mealPlan.totalWeight).formatted(
                    .number.precision(.fractionLength(0...2))) + " g").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                clearPackingButton
                if let cleared { undoClearButton(cleared) }
            }
        }
    }

    private var clearPackingButton: some View {
        Button("一键清空", systemImage: "eraser") {
            let own = store.inventory.packingItems
            let others = store.inventory.borrowedPackingItems
            if store.clearPackingList() {
                cleared = own
                clearedBorrowed = others
            }
        }.disabled(store.inventory.packingItems.isEmpty && store.inventory.borrowedPackingItems.isEmpty)
    }

    private func undoClearButton(_ items: [PackingItem]) -> some View {
        Button("撤销清空") {
            if store.restoreClearedPacking(own: items, borrowed: clearedBorrowed) {
                cleared = nil
                libraries.refreshBorrowedPackingItems()
            }
        }
    }

    private var equipmentBrowser: some View {
        GeometryReader { area in
            Group {
                if area.size.width < 900 {
                    VStack(alignment: .leading, spacing: 8) {
                        categoryChooser
                        equipmentList(compact: true)
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        GearCategoryBrowser(selection: $category, showPackingSelection: true)
                            .frame(width: min(270, max(180, area.size.width * 0.25)))
                        equipmentList(compact: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
        }
        .onChange(of: category) { _, _ in search = "" }
    }

    private var categoryChooser: some View {
        Menu {
            ForEach(categoryOptions, id: \.path) { option in
                categoryMenuOption(option)
            }
        } label: {
            HStack(spacing: 10) {
                GearCategoryIcon(name: folderName).foregroundStyle(GearDesign.accent)
                Text(folderName).fontWeight(.semibold).lineLimit(1)
                Text("\(categoryCount(for: category)) 项").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GearDesign.background, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .accessibilityLabel("装备分类：\(folderName)，\(categoryCount(for: category)) 项，点按更改")
    }

    @ViewBuilder
    private func categoryMenuOption(_ option: (title: String, path: String)) -> some View {
        let children = GearSubcategories.children(of: option.title)
        if children.isEmpty {
            Button {
                category = option.path
            } label: {
                Label("\(option.title) · \(categoryCount(for: option.path)) 项", systemImage: GearSubcategories.symbol(for: option.title))
            }
        } else {
            Menu {
                Button("全部 \(option.title) · \(categoryCount(for: option.path)) 项") {
                    category = option.path
                }
                ForEach(children, id: \.self) { child in
                    let path = "\(option.path)/\(child)"
                    Button("\(child) · \(categoryCount(for: path)) 项") {
                        category = path
                    }
                }
            } label: {
                Label("\(option.title) · \(categoryCount(for: option.path)) 项", systemImage: GearSubcategories.symbol(for: option.title))
            }
        }
    }

    private func categoryCount(for path: String) -> Int {
        let owned = store.items.filter { store.inventory.matchesCategoryFolder($0, path: path) }.count
        let borrowed = store.inventory.borrowedPackingItems.filter { matchesBorrowedFolder($0, path: path) }.count
        return owned + borrowed
    }

    private func equipmentList(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            equipmentListHeading
            equipmentSearch
            equipmentColumnHeadings
            equipmentRows(compact: compact)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var equipmentListHeading: some View {
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
    }

    private var equipmentColumnHeadings: some View {
        HStack {
            Text("装备名称")
            Spacer()
            Text("携带数量").frame(width: 150)
            Text("小计").frame(width: 110, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func equipmentRows(compact: Bool) -> some View {
        List {
            if !borrowed.isEmpty { borrowedEquipmentSection(compact: compact) }
            ownedEquipmentRows(compact: compact)
        }
        .overlay {
            if candidates.isEmpty && borrowed.isEmpty {
                Text(store.items.isEmpty ? "装备库暂无装备，请先在装备库录入" : "暂无符合条件的装备")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GearDesign.surface)
        .listRowBackground(GearDesign.surface)
    }
}

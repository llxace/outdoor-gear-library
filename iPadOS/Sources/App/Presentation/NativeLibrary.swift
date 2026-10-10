import SwiftUI
import UIKit

struct NativeLibrary: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @SceneStorage("librarySection") private var section = "打包"
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var filterStatus = "全部状态"
    @State private var filterCategory = "全部分类"
    @State private var ascending = true
    @State private var sort = "名称"
    @State private var draft: GearDraft?
    @FocusState private var focusedUser: UUID?
    @State private var switchingUser = false
    @State private var batch = false
    @State private var excelSource: ExcelImportSource?
    @State private var showingGearDetail = false
    let navigationItems = ["打包", "仪表盘", "个人专栏", "装备库", "设置", "回收站"]
    var current: Gear? {
        store.inventory.gear.first { selected.contains($0.id) && !store.inventory.extras($0.id).isLocation }
    }
    var records: [Gear] {
        let inventory = store.inventory
        return inventory.gear.filter { gear in
            let detail = inventory.extras(gear.id)
            if detail.isLocation { return false }
            if section == "回收站" { return gear.trashed && matchesSearch(gear) }
            if gear.trashed { return false }
            if filterStatus != "全部状态" && gear.status != filterStatus { return false }
            if !inventory.matchesCategoryFolder(gear, path: filterCategory) { return false }
            return matchesSearch(gear)
        }.sorted { ascending ? ordered($0, $1) : ordered($1, $0) }
    }
    func matchesSearch(_ gear: Gear) -> Bool {
        let detail = store.inventory.extras(gear.id)
        return search.isEmpty
            || [
                gear.name, gear.brand, gear.model, gear.notes, String(detail.assetID), detail.importRef,
                detail.description,
            ]
            .joined(separator: " ").localizedCaseInsensitiveContains(search)
    }
    func ordered(_ a: Gear, _ b: Gear) -> Bool {
        switch sort {
        case "资产编号": return store.inventory.extras(a.id).assetID < store.inventory.extras(b.id).assetID
        case "价格": return a.purchasePrice < b.purchasePrice
        case "重量": return a.weight < b.weight
        case "购买时间": return a.purchaseDate.localizedStandardCompare(b.purchaseDate) == .orderedAscending
        default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    private var userSwitchingPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("切换用户").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(libraries.users) { user in
                Button {
                    switchingUser = false
                    _ = libraries.select(user.id)
                } label: {
                    HStack(spacing: 10) {
                        UserAvatar(user: user, size: 28)
                        Text(user.name).lineLimit(1)
                        Spacer()
                        if user.id == libraries.selectedID {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    }.padding(8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .focused($focusedUser, equals: user.id)
                    .background(
                        focusedUser == user.id ? Color.primary.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .accessibilityLabel(user.name + (user.id == libraries.selectedID ? "，当前用户" : ""))
            }
        }.padding(12).frame(width: 230)
            .defaultFocus($focusedUser, libraries.selectedID)
    }
    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(navigationItems, id: \.self) { destination in
                        Button { section = destination } label: {
                            Label(destination, systemImage: icon(destination))
                                .foregroundStyle(section == destination ? GearDesign.accent : Color.primary)
                                .padding(.vertical, 3).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
                .listStyle(.sidebar).scrollContentBackground(.hidden).background(GearDesign.background)
                .tint(GearDesign.accent)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    userSwitcher
                }
        } detail: {
            content
        }
        .background(GearDesign.background)
        .toolbar {
            if section == "装备库" {
                ToolbarItem(placement: .primaryAction) {
                    Button("添加装备", systemImage: "plus") { create() }.disabled(!store.ready)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu("资料迁移", systemImage: "square.and.arrow.up.on.square") {
                    Button("导入 Excel") { store.chooseExcel { excelSource = $0 } }
                    Button("导入 CSV / TSV") { store.importCSV() }
                    Button("导出 CSV") { store.exportCSV() }
                    Divider()
                    Button("保存完整备份") { store.exportBackup() }
                    Button("恢复备份") { store.importBackup() }
                }
            }
        }
        .alert(
            "用户操作未完成", isPresented: Binding(get: { libraries.error != nil }, set: { if !$0 { libraries.error = nil } })
        ) {
            Button("好") { libraries.error = nil }
        } message: {
            Text(libraries.error ?? "")
        }
        .sheet(item: $draft) { draft in
            FullGearEditor(draft: draft).environmentObject(store).environmentObject(libraries)
        }
        .sheet(item: $excelSource) { source in ExcelImportView(source: source).environmentObject(store) }
        .sheet(isPresented: $batch) { BatchEditor(ids: selected).environmentObject(store) }
        .alert(
            store.error == nil ? "装备库" : "操作未完成",
            isPresented: Binding(
                get: { store.error != nil || store.notice != nil },
                set: {
                    if !$0 {
                        store.error = nil
                        store.notice = nil
                    }
                })
        ) {
            Button("好") {
                store.error = nil
                store.notice = nil
            }
        } message: {
            Text(store.error ?? store.notice ?? "")
        }
        .onChange(of: section) { _, _ in
            search = ""
            filterStatus = "全部状态"
            filterCategory = "全部分类"
            selected.formIntersection(Set(records.map(\.id)))
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportExcel"))) { _ in
            store.chooseExcel { excelSource = $0 }
        }
        .onAppear {
            if section == "装备清单" { section = "打包" }
            if !navigationItems.contains(section) { section = "打包" }
        }
    }
    private func navigationLinks(_ destinations: [String]) -> some View {
        ForEach(destinations, id: \.self) { destination in
            Label {
                Text(destination)
            } icon: {
                Image(systemName: icon(destination)).foregroundStyle(.secondary)
            }.font(.body).padding(.vertical, 2).tag(destination)
        }
    }
    @ViewBuilder var content: some View {
        switch section {
        case "仪表盘": DashboardView(open: { section = $0 }).environmentObject(store)
        case "个人专栏": HikeHistoryView().environmentObject(store)
        case "打包": PackingListView().environmentObject(store)
        case "设置": LibraryPreferences().environmentObject(store)
        default: inventoryList
        }
    }
    var inventoryList: some View {
        GeometryReader { area in
            let showsCategories = section == "装备库" && area.size.width >= 650
            let showsDetail = area.size.width >= 1050
            HStack(alignment: .top, spacing: 0) {
                if showsCategories {
                    GearCategoryBrowser(selection: $filterCategory, showPackingSelection: true)
                        .frame(width: min(250, max(185, area.size.width * 0.22)))
                    Divider()
                }
                equipmentBrowser
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                if showsDetail {
                    Divider()
                    detailPane.frame(width: min(390, max(320, area.size.width * 0.32)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GearDesign.background)
            .onChange(of: filterCategory) { _, _ in selected.formIntersection(Set(records.map(\.id))) }
            .onChange(of: selected) { _, newValue in
                if area.size.width < 1050 && newValue.count == 1 { showingGearDetail = true }
            }
            .sheet(isPresented: $showingGearDetail) {
                if let gear = current { gearDetail(gear) }
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let gear = current {
                gearDetail(gear)
            } else {
                ContentUnavailableView("选择装备", systemImage: "backpack", description: Text("选择一项装备查看完整档案。"))
            }
        }
    }

    private func gearDetail(_ gear: Gear) -> some View {
        FullGearDetail(
            gear: gear,
            edit: { draft = GearDraft(gear: gear, extras: store.inventory.extras(gear.id)) },
            open: { selected = [$0] },
            child: { create(parent: gear.id) }
        )
        .environmentObject(store)
    }
    func create(parent: UUID? = nil) {
        var detail = GearExtras()
        detail.isLocation = false
        detail.parentID = parent
        draft = GearDraft(extras: detail)
    }
    func icon(_ section: String) -> String {
        switch section {
        case "仪表盘": return "square.grid.2x2"
        case "个人专栏": return "book.closed"
        case "打包": return "suitcase.rolling"
        case "设置": return "gearshape"
        case "回收站": return "trash"
        default: return "backpack"
        }
    }

    private var userSwitcher: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                switchingUser.toggle()
            } label: {
                HStack(spacing: 10) {
                    UserAvatar(user: libraries.currentUser, size: 28)
                    Text(libraries.currentUser.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("切换用户，" + libraries.currentUser.name)
            .popover(isPresented: $switchingUser, arrowEdge: .bottom) {
                if #available(macOS 14, *) {
                    userSwitchingPanel.focusEffectDisabled()
                } else {
                    userSwitchingPanel
                }
            }
            .help("切换用户，每个用户有独立的装备库和装备清单")
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    private var gearRows: some View {
        List(records, selection: $selected) { gear in
            HStack(spacing: 10) {
                GearPhoto(filename: gear.photo).frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(gear.name).fontWeight(.medium)
                    Text(
                        "#\(store.inventory.extras(gear.id).assetID) · "
                            + (store.inventory.extras(gear.id).isLocation ? store.inventory.path(gear.id) : gear.status)
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(gear.purchasePrice > 0 ? store.money(gear.purchasePrice) : "未记录价格")
                    .font(.body.weight(.medium)).monospacedDigit()
                    .foregroundStyle(gear.purchasePrice > 0 ? Color.primary : Color.secondary)
            }.tag(gear.id)
        }.overlay {
            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "backpack").font(.largeTitle).foregroundStyle(.secondary)
                    Text("暂无符合条件的记录")
                    Button("添加") { create() }
                }
            }
        }
    }

    private var equipmentBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if section == "装备库" {
                    Label {
                        Text(filterCategory == "全部分类" ? "装备库" : String(filterCategory.split(separator: "/").last ?? ""))
                    } icon: {
                        GearCategoryIcon(
                            name: filterCategory == "全部分类"
                                ? "全部装备" : String(filterCategory.split(separator: "/").last ?? ""))
                    }.font(.title2.bold())
                } else {
                    Text(section).font(.title2.bold())
                }
                Spacer()
                Text("\(records.count) 条").foregroundStyle(.secondary)
            }.padding()
            TextField("搜索名称、编号、品牌或型号", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal)
            HStack {
                Picker("状态", selection: $filterStatus) {
                    ForEach(["全部状态", "可用", "想买", "借出", "损坏", "已出售"], id: \.self) { Text($0) }
                }.labelsHidden()
                Picker("排序", selection: $sort) { ForEach(["名称", "资产编号", "价格", "重量", "购买时间"], id: \.self) { Text($0) } }
                    .labelsHidden()
            }.padding(.horizontal).padding(.top, 8)
            HStack {
                Toggle("升序", isOn: $ascending)
            }.padding(.horizontal).padding(.bottom, 8)
            Divider()
            gearRows
            if selected.count > 1 {
                HStack {
                    Text("已选 \(selected.count) 条")
                    Spacer()
                    Button("批量操作") { batch = true }
                }.padding(12)
            }
        }.frame(minWidth: 0, idealWidth: 360, maxWidth: .infinity)
    }
}

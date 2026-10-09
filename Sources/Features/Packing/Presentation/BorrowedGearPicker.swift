import SwiftUI

struct BorrowedGearPicker: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @Environment(\.dismiss) private var dismiss
    @State private var owner: UUID?
    @State private var source: GearStore?
    @State private var failure: String?
    @State private var search = ""
    @State private var packingSection = "装备"
    @State private var category = "全部分类"
    private var otherUsers: [LibraryUser] { libraries.users.filter { $0.id != libraries.selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("添加别人的装备").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
            }
            Text("加入当前用户的打包清单，保留装备原来的所属用户。").foregroundStyle(.secondary)
            Picker("来源用户", selection: $owner) {
                Text("请选择用户").tag(nil as UUID?)
                ForEach(otherUsers) { Text($0.name).tag(Optional($0.id)) }
            }
            if let source, let owner {
                HSplitView {
                    GearCategoryBrowser(selection: $category).environmentObject(source).frame(
                        minWidth: 180, idealWidth: 220, maxWidth: 270)
                    VStack {
                        TextField("搜索名称、品牌或型号", text: $search).textFieldStyle(.roundedBorder)
                        List(
                            source.items.filter {
                                source.inventory.matchesCategoryFolder($0, path: category)
                                    && (search.isEmpty
                                        || [$0.name, $0.brand, $0.model].joined(separator: " ")
                                            .localizedCaseInsensitiveContains(search))
                            }
                        ) { gear in
                            HStack {
                                GearPhoto(filename: gear.photo).environmentObject(source).frame(width: 42, height: 42)
                                VStack(alignment: .leading) {
                                    Text(gear.name)
                                    Text(
                                        "\(gear.weight.formatted()) g / 件 · 库内 \(gear.quantity.formatted()) 件"
                                            + (gear.status == "损坏" ? " · 已损坏" : "")
                                    ).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let existing = store.inventory.borrowedPackingItems.first {
                                    $0.ownerID == owner && $0.gear.id == gear.id
                                }
                                Button(existing == nil ? "加入清单" : "已添加") {
                                    failure = nil
                                    do {
                                        let (copy, _) = try store.copyUnsavedGear(
                                            gear, extras: GearExtras(), from: source)
                                        let item = BorrowedPackingItem(
                                            ownerID: owner,
                                            ownerName: otherUsers.first { $0.id == owner }?.name ?? "其他用户", gear: copy,
                                            quantity: min(1, gear.quantity),
                                            subcategory: source.inventory.subcategory(for: gear))
                                        if !store.setBorrowedQuantity(item.quantity, item: item) {
                                            failure = store.error
                                            store.error = nil
                                        }
                                    } catch { failure = "无法加入装备：" + error.localizedDescription }
                                }.disabled(existing != nil || gear.status == "损坏")
                            }.padding(.vertical, 5).opacity(gear.status == "损坏" ? 0.45 : 1)
                        }
                    }.padding().frame(minWidth: 430)
                }
            } else {
                Text("选择其他用户，浏览其装备库。").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }.padding(24).frame(minWidth: 760, minHeight: 530)
            .onChange(of: owner) { id in
                source = id.flatMap { libraries.library(for: $0) }
                search = ""
                category = "全部分类"
                failure = source == nil ? libraries.error : nil
                libraries.error = nil
            }
            .onAppear { owner = otherUsers.first?.id }
    }
}

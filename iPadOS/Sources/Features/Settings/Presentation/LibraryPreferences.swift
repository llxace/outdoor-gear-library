import SwiftUI
import UIKit

struct LibraryPreferences: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @State private var settings = LibrarySettings()
    @State private var editingUser: LibraryUser?
    private var appearance: GearAppearance { GearAppearance(rawValue: store.inventory.settings.appearance) ?? .system }
    private var appearanceSelection: Binding<String> {
        Binding(
            get: { store.inventory.settings.appearance },
            set: { value in
                var next = store.inventory
                next.settings.appearance = value
                if store.commit(next) {
                    settings.appearance = value

                }
            })
    }
    var body: some View {
        Form {
            profileSection
            usersSection
            Section("外观") {
                Picker("颜色模式", selection: appearanceSelection) {
                    ForEach(GearAppearance.allCases) { mode in Text(mode.rawValue).tag(mode.rawValue) }
                }.pickerStyle(.segmented)
                Text(appearance.explanation).font(.caption).foregroundStyle(.secondary)
            }
            librarySection
            backupSection
            Section("快速整理与导入") {
                Text("把已有装备表导入资料库，后续按装备 ID 更新。").foregroundStyle(.secondary)
                Button("导入 Excel 表格", systemImage: "tablecells") {
                    NotificationCenter.default.post(name: Notification.Name("ImportExcel"), object: nil)
                }.buttonStyle(.borderedProminent).disabled(!store.ready)
                Text("导入前自动备份，可先预览再确认。").font(.caption).foregroundStyle(.secondary)
            }
            Section("整理工具") {
                Button("补齐缺失装备编号") { store.ensureIdentifiers() }
                Button("为没有主图的装备使用第一张照片") { store.setMissingPrimaryPhotos() }
                Button("标准化购买日期") { store.normalizeDates() }
            }
            Section("批量清理") {
                Button("将当前用户的全部装备移至回收站", role: .destructive) {
                    PadFileDialog.confirm("将当前用户的全部装备移至回收站？", "只影响“\(libraries.currentUser.name)”，可以在回收站批量恢复。") { accepted in
                        if accepted { _ = store.changeRecords(Set(store.items.map(\.id)), trash: true) }
                    }
                }
            }
            Section("关于") {
                Text(
                    "户外装备库 · "
                        + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"))
                Text("本机用户资料管理，支持装备清单与重量计算。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(GearDesign.background)
            .frame(maxWidth: 1000, maxHeight: .infinity, alignment: .top)
            .onAppear { settings = store.inventory.settings }
            .sheet(item: $editingUser) { user in UserProfileEditor(user: user).environmentObject(libraries) }
    }

    private var profileSection: some View {
        Section("个人资料") {
            HStack(spacing: 18) {
                UserAvatar(user: libraries.currentUser, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(libraries.currentUser.name).font(.title2.bold())
                    Text("当前用户 · 资料保存在本机").foregroundStyle(.secondary)
                    Text("\(store.items.count) 项装备 · 清单 \(store.inventory.packingGear.count) 项")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("编辑头像与用户名") { editingUser = libraries.currentUser }
            }.padding(.vertical, 10)
        }
    }

    private var usersSection: some View {
        Section("用户管理") {
            ForEach(libraries.users) { user in
                HStack(spacing: 12) {
                    UserAvatar(user: user, size: 32)
                    Text(user.name).lineLimit(1)
                    Spacer()
                    if user.id == libraries.selectedID {
                        Label("当前用户", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button("切换") { _ = libraries.select(user.id) }
                    }
                    Button("编辑资料") { editingUser = user }
                }.padding(.vertical, 4)
            }
            Button("新建用户", systemImage: "person.badge.plus") { editingUser = LibraryUser(id: UUID(), name: "") }
            Text("每个用户的装备、照片、装备清单和设置独立保存。新用户从空库开始。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var librarySection: some View {
        Section("装备库") {
            TextField("装备库名称", text: $settings.name)
            Picker("货币", selection: $settings.currency) {
                ForEach(["CNY", "USD", "EUR", "GBP", "JPY", "HKD", "TWD"], id: \.self) { Text($0) }
            }
            .onChange(of: settings.currency) { _, selected in
                var current = store.inventory.settings
                current.currency = selected
                store.saveSettings(current)
                Task { await store.refreshExchangeRates() }
            }
            Text(store.exchangeDescription).font(.caption).foregroundStyle(.secondary)
            if !store.exchangeError.isEmpty { Text(store.exchangeError).font(.caption).foregroundStyle(.secondary) }
            Button("刷新汇率") { Task { await store.refreshExchangeRates() } }
                .disabled(store.exchangeLoading || settings.currency == "CNY")
            Text("汇率为每日参考价；装备与路餐价格仍以 CNY 录入。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("自动生成装备编号", isOn: $settings.autoAssetID)
            Toggle("复制装备时包含照片与附件", isOn: $settings.copyAttachments)
            TextField("复制装备的名称前缀", text: $settings.copyPrefix)
            Button("保存装备库设置") {
                settings.appearance = store.inventory.settings.appearance
                if settings.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.error = "装备库名称不能为空。"
                    return
                }
                store.saveSettings(settings)
            }
        }
    }

    private var backupSection: some View {
        Section("备份与工具") {
            Text("以下操作只作用于当前用户：\(libraries.currentUser.name)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("保存完整备份") { store.exportBackup() }
                Button("恢复备份") { store.importBackup() }
                Button("导入 CSV / TSV") { store.importCSV() }
                Button("导出 CSV") { store.exportCSV() }
            }
            Button("分享当前用户的数据目录") { PadFileDialog.share(store.root) }
            Text("完整备份含装备、清单、照片和附件；CSV 仅含装备资料。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

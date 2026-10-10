import SwiftUI
import UIKit

struct HikeHistoryView: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @State private var search = ""
    @State private var selected: UUID?
    @State private var draft: HikeRecord?
    @State private var showDeleted = false
    @State private var importError: String?
    @State private var needsDate = false
    @State private var expandedRoute: HikingRoute?
    @State private var section = HikeSection.overview
    @State private var editorSection = HikeSection.overview
    private var selectionKey: String { "historySelection." + libraries.selectedID.uuidString }
    private var records: [HikeRecord] {
        store.inventory.hikeHistory.filter {
            $0.deleted == showDeleted && (search.isEmpty || [$0.title, $0.routeName, $0.notes]
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
    }
    private var years: [Int] { Set(records.map { Calendar.current.component(.year, from: $0.date) }).sorted(by: >) }
    private var current: HikeRecord? { records.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            historyHeading
            if let importError {
                Label("导入失败：" + importError, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                historyList
                if let record = current {
                    HikeRecordDetail(record: record, section: $section, edit: {
                        needsDate = false
                        editorSection = .overview
                        draft = record
                    }, addEquipment: {
                        needsDate = false
                        editorSection = .equipment
                        draft = record
                    }, expandRoute: { expandedRoute = $0 })
                } else {
                    emptyDetail
                }
            }
        }
        .padding(20).background(HikeStyle.background)
        .tint(HikeStyle.accent).accentColor(HikeStyle.accent)
        .sheet(item: $draft) {
            HikeRecordEditor(record: $0, needsDate: needsDate, section: $editorSection)
                .environmentObject(store)
        }
        .sheet(item: $expandedRoute) {
            ExpandedRouteMap(route: $0, terrain: RouteTerrain.recorded($0), error: nil)
        }
        .onAppear { restoreSelection() }
        .onChange(of: records.map(\.id)) { _, _ in selectAvailableRecord() }
        .onChange(of: selected) { _, value in
            if !showDeleted, let value { UserDefaults.standard.set(value.uuidString, forKey: selectionKey) }
        }
        .onChange(of: showDeleted) { _, _ in restoreSelection() }
    }

    private var historyHeading: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("个人专栏").font(.system(size: 22, weight: .bold))
                Text(libraries.currentUser.name + "的徒步档案").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("导入轨迹", systemImage: "square.and.arrow.down", action: importTrack)
                .buttonStyle(.borderedProminent).tint(HikeStyle.control)
            Menu {
                Link("两步路轨迹导出说明", destination: URL(string: "https://www.2bulu.com/community/gotohuatinfo.htm?id=489")!)
            } label: { Image(systemName: "info.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("轨迹导入说明").accessibilityLabel("轨迹导入说明")
            Menu {
                Button("保存当前打包", systemImage: "suitcase.rolling") {
                    needsDate = false
                    editorSection = .overview
                    draft = store.hikeFromPacking()
                }
                Button("手动补录", systemImage: "square.and.pencil") {
                    needsDate = false
                    editorSection = .overview
                    draft = HikeRecord()
                }
            } label: { Label("新建记录", systemImage: "plus") }
                .fixedSize().foregroundStyle(HikeStyle.accent)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("搜索行程、路线或游记", text: $search).textFieldStyle(.roundedBorder)
                Menu {
                    Toggle("查看已删除记录", isOn: $showDeleted)
                } label: { Image(systemName: showDeleted ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("筛选记录").accessibilityLabel("筛选记录")
            }
            if showDeleted { Label("已删除记录", systemImage: "trash").font(.caption).foregroundStyle(.secondary) }
            List(selection: $selected) {
                ForEach(years, id: \.self) { year in
                    Section {
                        ForEach(records.filter { Calendar.current.component(.year, from: $0.date) == year }) { record in
                            recordRow(record).tag(record.id)
                        }
                    } header: { Text(String(year)).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .overlay {
                    if records.isEmpty {
                        Text(search.isEmpty ? (showDeleted ? "暂无已删除记录" : "还没有徒步记录") : "没有符合条件的记录")
                            .foregroundStyle(.secondary)
                    }
                }
        }.padding(12).background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 300)
    }

    private func recordRow(_ record: HikeRecord) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(selected == record.id ? HikeStyle.accent : .clear).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                Text(record.gear.isEmpty ? "未记录装备" : "\(record.gear.count) 项装备 · \(HikeStyle.kilograms(record.weight)) kg")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
            .listRowBackground(selected == record.id ? HikeStyle.selection : Color.clear)
            .listRowSeparator(.hidden)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed").font(.system(size: 34)).foregroundStyle(HikeStyle.accent)
            Text(search.isEmpty ? "留下每一次徒步" : "没有符合条件的行程").font(.headline)
            Text(search.isEmpty ? "导入历史轨迹，或补录路线、装备与回忆。" : "试试其他关键词，或清空搜索。")
                .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restoreSelection() {
        let saved = UserDefaults.standard.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
        selected = records.first(where: { $0.id == saved })?.id ?? records.first?.id
    }

    private func selectAvailableRecord() {
        if !records.contains(where: { $0.id == selected }) { selected = records.first?.id }
    }

    private func importTrack() {
        chooseHistoricalTrack { result in
            switch result {
            case .success(let imported):
                guard let imported else { return }
                importError = nil; needsDate = imported.recordedDate == nil
                editorSection = .overview; draft = imported.record
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }
}

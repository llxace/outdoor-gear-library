import SwiftUI
import AppKit

struct HikeRecordEditor: View {
    @EnvironmentObject var store: GearStore
    @Environment(\.dismiss) private var dismiss
    @State var record: HikeRecord
    @State var needsDate = false
    @State private var dateVerified = false
    @State private var failure: String?
    @State private var showingGearPicker = false
    @Binding var section: HikeSection

    init(record: HikeRecord, needsDate: Bool = false, section: Binding<HikeSection>) {
        _record = State(initialValue: record)
        _needsDate = State(initialValue: needsDate)
        _section = section
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(record.title.isEmpty ? "新建徒步记录" : "编辑徒步记录").font(.system(size: 22, weight: .semibold))
            Picker("编辑内容", selection: $section) {
                Text("基本信息").tag(HikeSection.overview)
                Text("当次装备 \(record.gear.count)").tag(HikeSection.equipment)
                Text("徒步回忆").tag(HikeSection.memories)
            }.pickerStyle(.segmented).labelsHidden().tint(HikeStyle.control)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section {
                    case .overview: basicInformation
                    case .equipment:
                        equipmentSnapshotActions
                        HistoricalEquipmentEditor(items: $record.gear)
                        Text("历史数量按实际携带填写；本页不会修改库存或当前打包清单。")
                            .font(.caption).foregroundStyle(.secondary)
                    case .memories:
                        Text("游记、天气和装备使用感受").font(.headline)
                        TextEditor(text: $record.notes).font(.system(size: 15)).frame(minHeight: 360)
                            .padding(8).background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                    }
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            Divider()
            HStack {
                Text("合计 \(HikeStyle.kilograms(record.weight)) kg").monospacedDigit().fontWeight(.medium)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存记录", action: saveRecord).buttonStyle(.borderedProminent).tint(HikeStyle.control)
                    .disabled(needsDate && !dateVerified).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 780, height: 640).background(HikeStyle.background)
            .tint(HikeStyle.accent).accentColor(HikeStyle.accent)
            .sheet(isPresented: $showingGearPicker) {
                HistoricalGearPicker(items: store.items, existing: record.gear) { additions in
                    record.gear = HistoryEquipment.adding(additions, to: record.gear)
                }
            }
    }

    private var basicInformation: some View {
        VStack(alignment: .leading, spacing: 20) {
            if needsDate {
                Label("文件未提供有效徒步时间，请填写当时真实日期。", systemImage: "calendar.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            }
            labeledField("记录标题", text: $record.title, placeholder: "例如 五台山2026")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("徒步日期").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DatePicker("徒步日期", selection: $record.date, displayedComponents: .date).labelsHidden()
                        .onChange(of: record.date) { _ in dateVerified = true }
                }.frame(maxWidth: .infinity, alignment: .leading)
                labeledField("里程", text: $record.distance, placeholder: "例如 15 km，可留空")
            }
            if needsDate { Toggle("我已核对这次徒步的历史日期", isOn: $dateVerified) }
            labeledField("路线 / 地点", text: $record.routeName, placeholder: "路线名称或起终点")
            Divider()
            historicalRouteActions
            VStack(alignment: .leading, spacing: 8) {
                Text("轨迹文件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(record.route?.importedFile ?? (record.route == nil ? "未添加轨迹" : "已关联路线"))
                    .font(.callout).textSelection(.enabled)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }

    private func saveRecord() {
        guard record.isValid else {
            failure = "请填写标题及装备名称，重量不可为负，数量须大于 0。"
            return
        }
        if store.saveHike(record) { dismiss() } else {
            failure = store.error
            store.error = nil
        }
    }

    private var historicalRouteActions: some View {
        HStack {
            Text("历史路线").font(.headline)
            Spacer()
            Button("导入 / 更换 GPX、KML") {
                do {
                    if let imported = try chooseHistoricalTrack() {
                        record.route = imported.route
                        record.routeName = imported.route.name
                        record.distance = imported.route.distance
                        if record.title.isEmpty { record.title = imported.route.name }
                        if let date = imported.recordedDate { record.date = date }
                        needsDate = imported.recordedDate == nil
                        dateVerified = !needsDate
                    }
                } catch { failure = error.localizedDescription }
            }
            if record.route != nil { Button("移除轨迹") { record.route = nil } }
        }
    }

    private var equipmentSnapshotActions: some View {
        HStack {
            Text("当次携带装备").font(.headline)
            Spacer()
            Menu("添加装备", systemImage: "plus") {
                Button("从当前打包添加（\(store.hikeFromPacking().gear.count) 项）") {
                    record.gear = HistoryEquipment.adding(store.hikeFromPacking().gear, to: record.gear)
                }.disabled(store.hikeFromPacking().gear.isEmpty)
                Button("从装备库选择…") { showingGearPicker = true }
                Button("手动添加装备") {
                    var gear = Gear()
                    gear.name = ""
                    record.gear.append(HikeGear(gear: gear, quantity: 1))
                }
            }.foregroundStyle(HikeStyle.accent)
        }
    }
}

import SwiftUI
import AppKit

enum HikeSection: String, CaseIterable, Identifiable {
    case overview = "行程概览", equipment = "当次装备", memories = "徒步回忆"
    var id: Self { self }
}

// 两种外观共享松绿色相；内容明度随系统外观变化。
enum HikeStyle {
    static let background = GearDesign.background
    static let surface = GearDesign.surface
    static let selection = GearDesign.selection
    static let accent = GearDesign.accent
    static let control = GearDesign.controls
    static func kilograms(_ grams: Double) -> String { (grams / 1000).formatted(.number.precision(.fractionLength(3))) }
    static func meters(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) + " m" } ?? "未记录"
    }
}

struct HikeRecordDetail: View {
    @EnvironmentObject var store: GearStore
    let record: HikeRecord
    @Binding var section: HikeSection
    let edit: () -> Void
    let addEquipment: () -> Void
    let expandRoute: (HikingRoute) -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            HStack(spacing: 28) {
                statistic(record.distance.isEmpty ? "未记录" : record.distance, label: "里程")
                statistic(record.gear.isEmpty ? "未记录" : "\(record.gear.count) 项", label: "携带装备")
                statistic(record.gear.isEmpty ? "—" : HikeStyle.kilograms(record.weight) + " kg", label: "装备总重量")
            }.padding(.vertical, 4)
            Picker("行程内容", selection: $section) {
                ForEach(HikeSection.allCases) { item in
                    Text(item == .equipment ? "当次装备 \(record.gear.count)" : item.rawValue).tag(item)
                }
            }.pickerStyle(.segmented).labelsHidden().tint(HikeStyle.control)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .overview: overview
                    case .equipment: equipment
                    case .memories: memories
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.id(section)
        }.padding(.leading, 24).padding(.vertical, 8).frame(minWidth: 400)
            .confirmationDialog("删除“\(record.title)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { setDeleted(true) }
            } message: { Text("可在已删除记录中恢复。") }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                Text(record.title).font(.system(size: 24, weight: .semibold)).textSelection(.enabled)
                Spacer(minLength: 0)
                if record.deleted {
                    Button("恢复记录") { setDeleted(false) }
                } else {
                    Button("编辑", action: edit).foregroundStyle(HikeStyle.accent)
                    Menu {
                        Button("删除记录", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多记录操作")
                }
            }
            Text([record.date.formatted(date: .long, time: .omitted), record.routeName]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let route = record.route {
                HStack {
                    Label("路线地图", systemImage: "map").font(.headline)
                    Spacer()
                    Button("放大", systemImage: "arrow.up.left.and.arrow.down.right") { expandRoute(route) }
                        .foregroundStyle(HikeStyle.accent)
                }
                RouteMap(route: route, mapType: .standard).id(record.id).frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let terrain = RouteTerrain.recorded(route) { terrainSummary(terrain) }
                if !record.notes.isEmpty && record.notes.contains("参考轨迹") && record.notes.contains("复原") {
                    Label("回忆中注明：此路线依据参考轨迹复原，非本人当时记录。", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("轨迹来源") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let filename = route.importedFile { Text("导入文件：" + filename).textSelection(.enabled) }
                        Link(route.importedFile != nil || route.destinationOnly == true ? "在 Apple 地图中查看地点" : "原始路线资料",
                            destination: route.sourceURL).foregroundStyle(HikeStyle.accent)
                    }.font(.caption).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(12).background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                emptyState("未记录轨迹", detail: "可以编辑这次记录，补充 GPX 或 KML 路线。", action: "补充路线")
            }
            if let plan = record.mealPlan, !plan.foods.isEmpty || plan.waterLiters > 0 {
                GearPanel(title: "当次路餐", symbol: "fork.knife") {
                    Text("路餐与水重量 " + plan.totalWeight.formatted() + " g · 热量 " + plan.calories.formatted() + " kcal")
                    Text(plan.shoppingList).textSelection(.enabled)
                }
            }
        }
    }

    private var equipment: some View {
        VStack(alignment: .leading, spacing: 16) {
            if record.gear.isEmpty {
                emptyState(
                    "未记录装备", detail: "补充当时实际携带的装备，留存这次徒步的清单。",
                    action: "补充当次装备", perform: addEquipment)
            } else {
                Text("\(record.gear.count) 项 · \(HikeStyle.kilograms(record.weight)) kg").font(.headline).monospacedDigit()
                Text("这是当次装备快照；装备库的后续修改不会改变这份历史。").font(.caption).foregroundStyle(.secondary)
                if record.gear.contains(where: { $0.gear.weight == 0 }) {
                    Label("部分装备未填重量，仅合计已知重量。", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                HistoricalEquipmentSummary(items: record.gear).id(record.id)
            }
        }
    }

    private var memories: some View {
        Group {
            if record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState("还没有记录这次徒步的感受", detail: "写下沿途见闻、天气和装备使用感受。", action: "添加回忆")
            } else {
                Text(record.notes).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading).padding(20)
                    .background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func statistic(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terrainSummary(_ terrain: RouteTerrain) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                statistic(HikeStyle.meters(terrain.ascent), label: "累计爬升")
                statistic(HikeStyle.meters(terrain.descent), label: "累计下降")
                statistic(HikeStyle.meters(terrain.low) + "–" + HikeStyle.meters(terrain.high), label: "海拔范围")
            }
            Text("平均海拔 \(HikeStyle.meters(terrain.average)) · 轨迹高程估算").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func emptyState(
        _ title: String, detail: String, action: String, perform: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
            if !record.deleted { Button(action, action: perform ?? edit).foregroundStyle(HikeStyle.accent) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(HikeStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func setDeleted(_ deleted: Bool) {
        var updated = record
        updated.deleted = deleted
        _ = store.saveHike(updated)
    }
}

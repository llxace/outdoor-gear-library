import SwiftUI
import AppKit
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: GearStore
    let open: (String) -> Void
    @State private var statisticMode = EquipmentStatistic.categoryQuantity
    @State private var showAllGroups = false
    private var allGroups: [Distribution] {
        statisticMode.distribution(store.items).map {
            Distribution(name: $0.name, value: statisticMode.isCost ? store.convertedMoney($0.value) : $0.value)
        }
    }
    private var chartGroups: [Distribution] { showAllGroups ? allGroups : Array(allGroups.prefix(8)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overviewHeading
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 175)), count: 2), spacing: 14) {
                    statistic("在库装备", "\(store.items.count)", "backpack", "装备库", "查看装备库")
                    statistic(
                        "购置支出",
                        store.money(store.inventory.items.filter { !$0.trashed }.reduce(0) { $0 + $1.purchasePrice }),
                        "creditcard", "装备库", "查看装备购买信息")
                }
                overviewCards
            }.padding(28).frame(maxWidth: 1240, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
        }.background(GearDesign.background)
    }
    func statistic(_ title: String, _ value: String, _ symbol: String, _ section: String, _ hint: String) -> some View {
        Button {
            open(section)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: symbol).foregroundStyle(GearDesign.accent)
                }
                Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(.primary).minimumScaleFactor(0.8)
                    .lineLimit(1)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .help(hint).accessibilityLabel(title + "，" + value + "，" + hint)
    }

    private var overviewHeading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("装备概览").font(.title.bold())
                Text("\(store.items.count) 件装备").font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            Label("本机资料库", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var overviewCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), alignment: .top)], alignment: .leading, spacing: 20) {
            distributionPanel
            equipmentOverview

        }
    }

    private var distributionPanel: some View {
        GearPanel(title: "装备统计", symbol: "chart.bar.xaxis") {
            if chartGroups.isEmpty {
                Text("添加或导入装备后，这里会显示统计图表。").foregroundStyle(.secondary).padding(.vertical, 32)
            } else {
                Chart(chartGroups) { entry in
                    BarMark(x: .value(statisticMode.rawValue, entry.value), y: .value("分组", entry.name))
                        .foregroundStyle(GearDesign.accent).cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text(statisticMode.formatted(entry.value, currency: store.displayCurrency))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: chartGroups.map(\.name))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
                .frame(height: CGFloat(max(180, chartGroups.count * 36)))
                .accessibilityLabel(statisticMode.rawValue)
                .accessibilityValue(
                    chartGroups.map {
                        "\($0.name)，\(statisticMode.formatted($0.value, currency: store.displayCurrency))"
                    }.joined(separator: "；"))
            }
            Text(statisticMode.explanation).font(.caption).foregroundStyle(.secondary)
            if statisticMode.isWeight && store.items.contains(where: { $0.weight == 0 }) {
                Text("\(store.items.filter { $0.weight == 0 }.count) 项未填重量，仅合计已知重量。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("显示 \(chartGroups.count) 组 · 共 \(allGroups.count) 组").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if allGroups.count > 8 {
                    Button(showAllGroups ? "收起" : "显示全部") { showAllGroups.toggle() }.buttonStyle(.plain)
                        .foregroundStyle(GearDesign.accent)
                }
                Button("装备库", systemImage: "arrow.right") { open("装备库") }.buttonStyle(.plain).foregroundStyle(
                    GearDesign.accent)
            }
        }.overlay(alignment: .topTrailing) {
            Picker("统计方式", selection: $statisticMode) {
                ForEach(EquipmentStatistic.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().controlSize(.small).frame(width: 160).padding(18)
        }.onChange(of: statisticMode) { _ in showAllGroups = false }
    }

    private var equipmentOverview: some View {
        GearPanel(title: "装备速览", symbol: "backpack") {
            let favorites = store.items.filter { store.inventory.isFavorite($0.id) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(favorites) { record in
                        HStack(alignment: .top, spacing: 12) {
                            GearPhoto(filename: record.photo).frame(width: 52, height: 52).accessibilityLabel(
                                record.name + "的缩略图")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.name).font(.body.weight(.medium)).fixedSize(
                                    horizontal: false, vertical: true)
                                Text(record.category + " · " + record.status).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }.padding(.vertical, 10)
                    }
                    if favorites.isEmpty {
                        Text("暂无收藏装备，到装备库打开装备详情并点击星标添加。").foregroundStyle(.secondary).padding(.vertical, 32)
                    }
                }
            }.frame(height: 360)
            Text("\(favorites.count) 件收藏装备 · 上下滚动查看").font(.caption).foregroundStyle(.secondary)
            Button("查看装备库", systemImage: "arrow.right") { open("装备库") }.buttonStyle(.plain).foregroundStyle(
                GearDesign.accent)
        }
    }
}

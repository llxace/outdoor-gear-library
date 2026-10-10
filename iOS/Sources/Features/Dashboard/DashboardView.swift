import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var library: GearLibrary
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var spending: Double { library.activeGear.reduce(0) { $0 + $1.purchasePrice } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("装备概览").font(.largeTitle.bold())
                        Text("户外装备库 · 本机资料").foregroundStyle(.secondary)
                    }
                    if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12) { metricCards } }
                    else { metricCards }
                    if let route = library.selectedRoute {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("当前路线", systemImage: "map.fill").font(.headline).foregroundStyle(OutdoorPalette.accent)
                            Text(route["name"] as? String ?? "已保存路线").font(.title3.bold())
                            HStack {
                                Label(route["area"] as? String ?? "", systemImage: "mappin.and.ellipse")
                                Spacer()
                                Text(route["distance"] as? String ?? "").foregroundStyle(OutdoorPalette.warm)
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("装备速览").font(.title3.bold())
                        ForEach(library.activeGear.prefix(8)) { gear in GearRow(gear: gear) }
                        if library.activeGear.isEmpty { ContentUnavailableView("还没有装备资料", systemImage: "backpack", description: Text("到“资料”页导入 Mac 上的装备库 JSON 文件。")) }
                    }.cardStyle()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("徒步记录").font(.title3.bold()); Spacer(); Text("\(library.hikeHistory.count) 条").foregroundStyle(.secondary) }
                        ForEach(Array(library.hikeHistory.prefix(3).enumerated()), id: \.offset) { _, hike in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hike["title"] as? String ?? hike["routeName"] as? String ?? "徒步记录").font(.headline)
                                HStack { Text(hike["date"] as? String ?? "历史记录"); Spacer(); Text(hike["distance"] as? String ?? "") }.font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                }.padding()
            }
            .background(OutdoorPalette.background.ignoresSafeArea())
            .navigationTitle("户外装备库")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var metricCards: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "在库装备", value: "\(library.activeGear.count)", icon: "backpack")
            MetricCard(title: "购买支出", value: spending.formatted(.currency(code: "CNY")), icon: "creditcard", valueColor: OutdoorPalette.warm)
            MetricCard(title: "打包件数", value: "\(library.packingItems.count)", icon: "checklist")
            MetricCard(title: "打包重量", value: "\((library.packedWeight / 1000).formatted(.number.precision(.fractionLength(2)))) kg", icon: "scalemass")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(OutdoorPalette.accent)
                Text(title).foregroundStyle(.secondary)
            }.font(.subheadline)
            Text(value).font(.title2.bold()).foregroundStyle(valueColor).minimumScaleFactor(0.8).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
}

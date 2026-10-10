import SwiftUI
import MapKit
import Charts

struct RouteMetricSummary: View {
    let route: HikingRoute
    let terrain: RouteTerrain?
    let error: String?
    var compact = false
    private func meters(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) + " m" } ?? "—"
    }
    private var distance: String {
        String(route.distance.split(separator: "（").first ?? "—").trimmingCharacters(in: .whitespaces)
    }
    private var elevationNote: String {
        if route.elevationStats != nil { return "SRTM90 m 估算" }
        return terrain?.ascent == nil ? "沿线采样估算" : "轨迹文件高程"
    }
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                Label(
                    distance + " · 海拔 " + meters(terrain?.low) + "–" + meters(terrain?.high),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if let average = terrain?.average { Label("平均海拔 " + meters(average), systemImage: "equal") }
                Label(
                    "爬升 " + meters(terrain?.ascent) + " · 下降 " + meters(terrain?.descent), systemImage: "arrow.up.right"
                )
            }.font(.caption).foregroundStyle(.secondary).help(terrain?.source ?? "等待海拔数据")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("路线概览").font(.headline)
                routeMetrics
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                elevationSources
                Spacer(minLength: 0)
            }
        }
    }
    private func metric(_ title: String, value: String, icon: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.body).foregroundStyle(GearDesign.accent)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var routeMetrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric(
                "路线长度", value: distance, icon: "point.topleft.down.to.point.bottomright.curvepath",
                note: route.distance.contains("估算") ? "地图估算" : "来源标注")
            metric(
                route.selectedSectionCount == nil ? "轨迹片段" : "已选徒步段",
                value: "\(route.selectedSectionCount ?? route.segments.count)", icon: "map",
                note: route.selectedSectionCount == nil ? "\(route.segments.reduce(0) { $0 + $1.count }) 个轨迹点" : "自定义组合"
            )
            metric("最高海拔", value: meters(terrain?.high), icon: "mountain.2", note: elevationNote)
            metric("最低海拔", value: meters(terrain?.low), icon: "arrow.down.to.line", note: elevationNote)
            metric("平均海拔", value: meters(terrain?.average), icon: "equal", note: "沿线等距采样")
            metric(
                "累计爬升", value: meters(terrain?.ascent), icon: "arrow.up.right",
                note: route.elevationStats == nil ? (terrain?.ascent == nil ? "需含高程轨迹" : "轨迹统计") : "90 m DEM 估算")
            metric(
                "累计下降", value: meters(terrain?.descent), icon: "arrow.down.right",
                note: route.elevationStats == nil ? (terrain?.descent == nil ? "需含高程轨迹" : "轨迹统计") : "90 m DEM 估算")
        }
    }

    private var elevationSources: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let stats = route.elevationStats {
                Link("SRTM90m · Open Topo Data", destination: URL(string: "https://www.opentopodata.org/api/")!).font(
                    .caption)
                Text("沿线 \(stats.profileSampleCount) 点采样，最高、最低、平均海拔及累计升降均为估算值。长路线的稀疏采样可能低估局部起伏。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if terrain?.ascent != nil {
                Label("来自轨迹文件高程", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                Text("累计升降未去噪，GPS 波动可能影响结果。").font(.caption2).foregroundStyle(.secondary)
            } else {
                Link(
                    "Open-Meteo · Copernicus DEM",
                    destination: URL(string: "https://open-meteo.com/en/docs/elevation-api")!
                ).font(.caption)
                Text("90 m 地形数据，沿线采样估算海拔。缺少连续高程时，不推算累计爬升。").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.top, 2)
    }
}

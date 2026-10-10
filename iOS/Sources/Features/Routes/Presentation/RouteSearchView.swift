import SwiftUI
import MapKit
import Charts

struct RouteSearchView: View {
    @EnvironmentObject var store: GearStore
    @StateObject private var model = RouteSearchModel()
    @Environment(\.dismiss) private var dismiss
    @State private var mapType = MKMapType.standard
    @State private var detailRefresh = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("选择徒步路线").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }
            HStack {
                Spacer()
                Button("导入 GPX / KML", systemImage: "square.and.arrow.down") { importTrack() }
            }
            Picker("搜索方式", selection: $model.byName) {
                Text("按地点找附近路线").tag(false)
                Text("按路线名称搜索").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                TextField(model.byName ? "输入徒步路线名称" : "输入城市、景区或山名", text: $model.query).textFieldStyle(.roundedBorder)
                    .onSubmit { model.searchPlaces() }
                if !model.byName {
                    Picker("附近范围", selection: $model.radius) {
                        ForEach([10, 30, 60], id: \.self) { Text("\($0) km").tag($0) }
                    }.frame(width: 190)
                }
                Button("搜索") { model.searchPlaces() }.disabled(
                    model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
            if model.busy {
                HStack {
                    ProgressView("正在搜索…").controlSize(.small)
                    Button("取消搜索") {
                        model.stopSearch()
                    }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.secondary) }
            if !model.places.isEmpty {
                Text("选择你要去的地点").font(.headline)
                ForEach(model.places) { place in Button(place.name) { model.searchRoutes(place) }.disabled(model.busy) }
            }
            HSplitView {
                routeResults
                routePreview
            }
            HStack {
                Text("本地路线库与在线路线合并搜索 · Waymarked Trails / © OpenStreetMap contributors · 覆盖因地区而异。").font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("导出说明", destination: URL(string: "https://www.2bulu.com/community/gotohuatinfo.htm?id=489")!)
                Link("来源与许可", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }.padding(24).frame(minWidth: 760, idealWidth: 880, minHeight: 550, idealHeight: 620)
            .task(id: "\(model.selectedID ?? 0)-\(detailRefresh)") { await model.loadPreview() }
            .onChange(of: model.byName) { _ in
                model.resetSearch()
            }
            .onDisappear { model.cancelSearch() }
    }
    private func importTrack() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["gpx", "kml"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let route = try TrackFileRepository.read(url)
            model.error = nil
            model.routes = [route]
            model.selectedID = route.id
        } catch { model.error = "导入失败：" + error.localizedDescription }
    }
    private func routeSummary(_ route: HikingRoute) -> String {
        let distance = route.distance.isEmpty ? "徒步路线" : route.distance
        let stats = route.elevationStats
        let elevation =
            stats.map {
                " · 海拔 \(Int($0.minimumMeters))–\(Int($0.maximumMeters)) m · ↑\(Int($0.estimatedAscentMeters)) ↓\(Int($0.estimatedDescentMeters)) m"
            } ?? ""
        return "\(route.area) · \(distance)\(elevation)"
    }
    private var routeResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.selectedRouteIDs.isEmpty {
                Label("已选 \(model.selectedRouteIDs.count) 段", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GearDesign.accent)
                Text("勾选多个分段，地图和路线数据会按所选内容汇总。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(model.routes) { route in
                    HStack(spacing: 10) {
                        Button {
                            model.selectedID = route.id
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(route.name).fontWeight(.medium)
                                Text(routeSummary(route)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("预览 \(route.name)")
                        Button {
                            model.toggleSelection(route)
                        } label: {
                            Image(
                                systemName: model.selectedRouteIDs.contains(route.id)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.title3).foregroundStyle(
                                model.selectedRouteIDs.contains(route.id) ? GearDesign.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(model.selectedRouteIDs.contains(route.id) ? "从自定义路线中移除" : "加入自定义路线")
                        .accessibilityLabel(
                            model.selectedRouteIDs.contains(route.id) ? "移除 \(route.name)" : "选择 \(route.name)")
                    }.padding(.vertical, 5)
                }
            }
        }.frame(minWidth: 240, idealWidth: 270, maxWidth: 350)
    }

    private var routePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.selectionLoading.isEmpty {
                ProgressView("正在读取所选分段轨迹…").controlSize(.small)
            }
            if let preview = model.displayedRoute {
                Text(model.combinedSelection == nil ? preview.name : "自定义路线 · 共选 \(model.selectedRouteIDs.count) 段")
                    .font(.headline)
                HStack {
                    Text("里程：" + (preview.distance.isEmpty ? "来源未标注" : preview.distance)).font(.callout)
                    Spacer()
                    Picker("地图", selection: $mapType) {
                        Text("标准地图").tag(MKMapType.standard)
                        Text("卫星地图").tag(MKMapType.hybrid)
                    }.frame(width: 180)
                }
                RouteMap(route: preview, mapType: mapType).frame(minHeight: 220)
                if preview.elevationStats != nil {
                    RouteMetricSummary(
                        route: preview, terrain: RouteTerrain.recorded(preview), error: nil, compact: true)
                }
                if preview.segments.isEmpty {
                    Text(
                        preview.destinationOnly == true
                            ? "该地点附近未收录徒步路线。这里只设定天气目的地，不代表已有可行走轨迹。" : "来源未提供可显示的轨迹，仅显示路线中心位置。"
                    ).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Link(
                        preview.importedFile == "组合路线" || preview.destinationOnly == true
                            ? "查看地图位置" : preview.importedFile != nil ? "查看轨迹位置" : "查看原始路线资料",
                        destination: preview.sourceURL)
                    Spacer()
                    Button(preview.destinationOnly == true ? "设为目的地查看天气" : "选作本次路线") {
                        if store.selectRoute(preview) { dismiss() }
                    }.buttonStyle(.borderedProminent)
                }
            } else if let detailError = model.detailError {
                Text(detailError)
                Button("重新加载") { detailRefresh = UUID() }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "map").font(.system(size: 40)).foregroundStyle(GearDesign.accent)
                    Text(
                        model.searched && model.routes.isEmpty && !model.busy
                            ? "当前开源数据源未找到与“\(model.query)”匹配的路线。" : "搜索路线或导入 GPX / KML 文件，在这里查看地图。")
                    if model.searched && model.routes.isEmpty && model.byName && !model.busy {
                        Button("按地点搜索“\(model.query)”") { model.byName = false }
                        Text("切换后点搜索，可查附近路线；无轨迹时可设为天气目的地。").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding().frame(minWidth: 400)
    }
}

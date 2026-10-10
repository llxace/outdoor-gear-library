import SwiftUI

struct RoutePickerView: View {
    @EnvironmentObject private var library: GearLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var routes: [RouteSnapshot] = []
    @State private var onlineRoutes: [RouteSnapshot] = []
    @State private var loadingOnline = false
    @State private var loadingRouteID: Int64?
    @State private var onlineMessage: String?
    @State private var loading = true
    private let routeSearch = WaymarkedRouteSearchService()

    private var filtered: [RouteSnapshot] {
        guard !search.isEmpty else { return routes }
        let local = routes.filter { "\($0.name) \($0.area)".localizedCaseInsensitiveContains(search) }
        let ids = Set(local.map(\.id))
        return local + onlineRoutes.filter { !ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { route in
                Button {
                    Task { await choose(route) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name).font(.headline).foregroundStyle(.primary)
                        HStack {
                            Text(route.area)
                            if !route.distance.isEmpty { Text("· \(route.distance)") }
                            if route.area == "在线路线" { Image(systemName: "network").foregroundStyle(OutdoorPalette.accent) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(loadingRouteID != nil)
            }
            .overlay {
                if loading { ProgressView("读取路线目录…") }
                else if loadingOnline && filtered.isEmpty { ProgressView("正在搜索在线徒步路线…") }
                else if filtered.isEmpty, let onlineMessage { ContentUnavailableView(onlineMessage, systemImage: "wifi.exclamationmark", description: Text("请检查网络，或试试路线目录里的路线。")) }
                else if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                if loadingRouteID != nil { ProgressView("正在下载路线轨迹…").padding().background(.regularMaterial, in: Capsule()) }
            }
            .searchable(text: $search, prompt: "搜索路线或地区")
            .navigationTitle("选择路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { await loadCatalog() }
            .task(id: search) { await searchOnline() }
        }
    }

    private func loadCatalog() async {
        defer { loading = false }
        guard let url = Bundle.main.url(forResource: "DomesticRoutes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(RouteCatalog.self, from: data) else { return }
        routes = catalog.entries.map(\.route).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func searchOnline() async {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        onlineRoutes = []
        onlineMessage = nil
        guard query.count >= 2 else { return }
        loadingOnline = true
        defer { loadingOnline = false }
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            onlineRoutes = try await routeSearch.search(query)
            if onlineRoutes.isEmpty { onlineMessage = "没有找到在线路线" }
        } catch is CancellationError {
            return
        } catch {
            onlineMessage = error.localizedDescription
        }
    }

    private func choose(_ route: RouteSnapshot) async {
        loadingRouteID = route.id
        defer { loadingRouteID = nil }
        do {
            let selected: RouteSnapshot
            if route.area == "在线路线" { selected = try await routeSearch.details(for: route) }
            else { selected = route }
            library.selectRoute(selected)
            dismiss()
        } catch {
            library.alert = "无法加载路线：\(error.localizedDescription)"
        }
    }
}

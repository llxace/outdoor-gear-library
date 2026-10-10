import Foundation
import Combine

@MainActor final class RouteSearchModel: ObservableObject {
    @Published var query = ""
    @Published var radius = 30
    @Published var byName = true
    @Published var places: [TrailPlace] = []
    @Published var routes: [HikingRoute] = []
    @Published var selectedID: Int64?
    @Published var selectedRouteIDs = Set<Int64>()
    @Published var selectedRoutes: [Int64: HikingRoute] = [:]
    @Published var selectionLoading = Set<Int64>()
    @Published var preview: HikingRoute?
    @Published var placeForWeather: HikingRoute?
    @Published var busy = false
    @Published var detailLoading = false
    @Published var searched = false
    @Published var error: String?
    @Published var detailError: String?
    private var searchTask: Task<Void, Never>?
    private let provider: any RouteSearching
    init(provider: (any RouteSearching)? = nil) { self.provider = provider ?? LiveRouteSearch() }
    var routesInSelection: [HikingRoute] {
        routes.compactMap { selectedRoutes[$0.id] }
    }
    var combinedSelection: HikingRoute? { HikingRoute.combining(routesInSelection) }
    var displayedRoute: HikingRoute? { combinedSelection ?? preview ?? placeForWeather }
    func toggleSelection(_ route: HikingRoute) {
        if selectedRouteIDs.remove(route.id) != nil {
            selectedRoutes[route.id] = nil
            return
        }
        selectedRouteIDs.insert(route.id)
        if !route.segments.isEmpty {
            selectedRoutes[route.id] = route
            return
        }
        selectionLoading.insert(route.id)
        Task {
            do {
                let detail = try await provider.details(route)
                if selectedRouteIDs.contains(route.id) { selectedRoutes[route.id] = detail }
            } catch {
                if selectedRouteIDs.remove(route.id) != nil { self.error = "读取分段轨迹失败：" + error.localizedDescription }
            }
            selectionLoading.remove(route.id)
        }
    }
    func cancelSearch() {
        searchTask?.cancel()
    }
    func stopSearch() {
        cancelSearch()
        busy = false
    }
    func resetSearch() {
        cancelSearch()
        prepareSearch()
        busy = false
    }
    private func prepareSearch() {
        busy = true
        error = nil
        places = []
        routes = []
        selectedID = nil
        placeForWeather = nil
        searched = false
        selectedRouteIDs = []
        selectedRoutes = [:]
        selectionLoading = []
    }
    func searchPlaces() {
        guard !busy else { return }
        prepareSearch()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            do {
                if byName {
                    try await searchNamedRoutes(text)
                    return
                }
                let result = try await provider.places(text)
                try Task.checkCancellation()
                busy = false
                if result.count == 1 {
                    searchRoutes(result[0])
                } else {
                    places = result
                    if result.isEmpty { error = "没有找到地点，请尝试附近城市或景区名称。" }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = (byName ? "路线搜索失败：" : "地点搜索失败：") + error.localizedDescription
                    busy = false
                }
            }
        }
    }
    private func searchNamedRoutes(_ text: String) async throws {
        let result = try await provider.namedRoutes(text)
        try Task.checkCancellation()
        routes = result
        searched = true
        busy = false
    }
    func searchRoutes(_ place: TrailPlace) {
        prepareSearch()
        searchTask = Task {
            do {
                let result = try await provider.routes(near: place, radius: radius)
                try Task.checkCancellation()
                routes = result
                searched = true
                busy = false
                if result.isEmpty {
                    placeForWeather = HikingRoute(
                        id: Int64(Date().timeIntervalSince1970 * 1000), name: place.name, area: place.name,
                        center: place.point, distance: "", destinationOnly: true)
                }
            } catch {
                if !Task.isCancelled {
                    self.error = "路线搜索失败：" + error.localizedDescription
                    busy = false
                }
            }
        }
    }
    func loadPreview() async {

        preview = nil
        detailError = nil
        guard let selectedID, let route = routes.first(where: { $0.id == selectedID }) else {
            detailLoading = false
            return
        }
        detailLoading = true
        do {
            let result =
                route.importedFile != nil || !route.segments.isEmpty ? route : try await provider.details(route)
            try Task.checkCancellation()
            preview = result
            detailLoading = false
        } catch {
            if !Task.isCancelled {
                detailError = "轨迹加载失败：" + error.localizedDescription
                detailLoading = false
            }
        }

    }
}

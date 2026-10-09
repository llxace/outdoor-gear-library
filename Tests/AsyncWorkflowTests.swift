import Foundation

@MainActor final class RouteStub: RouteSearching {
    let route = HikingRoute(id: 42, name: "隔离路线", area: "测试", center: TrailPoint(lat: 39, lon: 112), distance: "1 km")
    var fail = false
    var block = false
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func details(_ route: HikingRoute) async throws -> HikingRoute { route }
    func namedRoutes(_ query: String) async throws -> [HikingRoute] {
        started = true
        if block { await withCheckedContinuation { continuation = $0 } }
        if fail { throw URLError(.notConnectedToInternet) }
        return [route]
    }
    func places(_ query: String) async throws -> [TrailPlace] { [TrailPlace(name: "地点", point: route.center)] }
    func routes(near place: TrailPlace, radius: Int) async throws -> [HikingRoute] { [] }
}
@MainActor final class ConditionsStub: TripConditionsProviding {
    var failure: Error?
    var block = false
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func terrain(_ route: HikingRoute) async throws -> RouteTerrain? {
        if let failure { throw failure }
        return RouteTerrain(low: 100, high: 200, average: 150, ascent: 100, descent: 0, source: "fixture")
    }
    func forecast(at point: TrailPoint, departure: Date) async throws -> WeatherForecast {
        started = true
        if block { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        return WeatherForecast(current: WeatherNow(time: "2026-10-09T12:00", temperature_2m: 10, apparent_temperature: 8, weather_code: 0), days: [], elevation: 100)
    }
    func outlook(at point: TrailPoint) async throws -> SeasonalOutlook {
        if let failure { throw failure }
        return SeasonalOutlook(weeks: [], months: [], timezone: .gmt)
    }
}
@main struct AsyncWorkflowChecks {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw NSError(domain: "AsyncChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        assertions += 1
    }
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw NSError(domain: "AsyncChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for state"])
    }
    @MainActor static func main() async throws {
        let provider = RouteStub(); let search = RouteSearchModel(provider: provider)
        search.query = "测试"; search.searchPlaces()
        try await waitFor { !search.busy }
        try expect(search.routes.count == 1 && search.searched, "named search success")
        search.selectedID = 42; await search.loadPreview()
        try expect(search.preview?.id == 42 && !search.detailLoading, "route preview")
        search.resetSearch(); try expect(search.routes.isEmpty && search.selectedID == nil && !search.busy, "reset search")
        provider.fail = true; search.searchPlaces(); try await waitFor { !search.busy }
        try expect(search.error?.hasPrefix("路线搜索失败：") == true, "search failure displayed")
        provider.fail = false; search.byName = false; search.searchPlaces(); try await waitFor { !search.busy }
        try expect(search.placeForWeather?.destinationOnly == true && search.searched, "empty nearby result retains destination")
        search.byName = true; provider.block = true; provider.started = false; search.searchPlaces()
        try await waitFor { provider.continuation != nil }
        search.stopSearch(); provider.continuation?.resume(); provider.continuation = nil
        try await Task.sleep(nanoseconds: 20_000_000)
        try expect(!search.busy && search.error == nil, "cancel search does not show error")
        try expect(search.routes.isEmpty && !search.searched, "cancelled search cannot publish stale routes")

        let weather = ConditionsStub(); let model = TripConditionsModel(provider: weather)
        let fixedNow = ISO8601DateFormatter().date(from: "2026-10-09T10:00:00+08:00")!
        let pastWeather = ConditionsStub()
        let pastModel = TripConditionsModel(provider: pastWeather, now: { fixedNow })
        let pastDeparture = ISO8601DateFormatter().date(from: "2026-10-08T11:35:00+08:00")!
        await pastModel.loadForecast(route: provider.route, departure: pastDeparture)
        try expect(pastModel.departureHasPassed && pastModel.forecast == nil && !pastWeather.started, "past departure is rejected before weather request")
        await model.loadTerrain(route: provider.route)
        try expect(model.terrain?.high == 200 && model.terrainError == nil, "terrain loaded")
        await model.loadForecast(route: provider.route, departure: Date())
        try expect(model.forecast?.current.temperature_2m == 10 && model.updated != nil && !model.loading, "forecast loaded")
        await model.loadOutlook(route: provider.route)
        try expect(model.outlook != nil && !model.outlookLoading, "outlook loaded")
        weather.failure = NSError(domain: "TripPlanning", code: 2, userInfo: [NSLocalizedDescriptionKey: "日期超出范围"])
        await model.loadForecast(route: provider.route, departure: Date())
        try expect(model.outsideForecastRange && model.forecast == nil && !model.loading, "out-of-range weather state")
        await model.loadOutlook(route: provider.route)
        try expect(model.outlook == nil && model.outlookError == "日期超出范围", "outlook failure")
        await model.loadTerrain(route: nil); await model.loadForecast(route: nil, departure: Date()); await model.loadOutlook(route: nil)
        try expect(model.terrain == nil && model.forecast == nil && model.outlook == nil && !model.loading && !model.outlookLoading, "route removal resets weather")
        weather.failure = nil; weather.block = true
        let task = Task { await model.loadForecast(route: provider.route, departure: Date()) }
        try await waitFor { weather.continuation != nil }
        task.cancel(); weather.continuation?.resume(); weather.continuation = nil; await task.value
        try expect(model.forecast == nil && model.error == nil, "cancelled weather response not published")
        let data = Data("""
        {"timezone":"Asia/Shanghai","utc_offset_seconds":28800,"weekly":{"time":["2026-10-05"],"temperature_2m_mean":[10],"temperature_2m_anomaly":[1],"precipitation_anomaly":[2]},"monthly":{"time":["2026-10-01"],"temperature_2m_mean":[9],"temperature_2m_anomaly":[0],"precipitation_anomaly":[-1]}}
        """.utf8)
        let outlook = try WeatherService.decodeSeasonalOutlook(data)
        try expect(outlook.weeks[0].end == "2026-10-11" && outlook.months[0].end == "2026-10-31", "weekly/monthly calendar boundaries")
        print("PASS: \(assertions) assertions; route search/preview/error/reset/cancel, destination fallback, terrain/weather/outlook success/error/range/removal/cancel, seasonal period decoding")
    }
}

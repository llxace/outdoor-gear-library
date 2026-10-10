import Foundation
import CoreLocation

@MainActor enum TripService {
    private static let routeAPI = "https://hiking.waymarkedtrails.org/api/v1"
    private static var routeCache: [String: Data] = [:]

    static func places(_ query: String) async throws -> [TrailPlace] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = text == "五台山" ? "山西省忻州市五台山风景名胜区" : text
        let marks = try await CLGeocoder().geocodeAddressString(address)
        return marks.compactMap { mark in
            guard let coordinate = mark.location?.coordinate else { return nil }
            let names = [mark.name, mark.locality, mark.administrativeArea, mark.country].compactMap { $0 }
            var unique: [String] = []
            for name in names where !unique.contains(name) { unique.append(name) }
            return TrailPlace(
                name: unique.joined(separator: " · "),
                point: TrailPoint(lat: coordinate.latitude, lon: coordinate.longitude))
        }
    }

    private static func routeData(_ path: String, items: [URLQueryItem] = []) async throws -> Data {
        var url = URLComponents(string: routeAPI + path)!
        url.queryItems = items.isEmpty ? nil : items
        let key = url.url!.absoluteString
        if let cached = routeCache[key] { return cached }
        let data = try await TripHTTPClient.request(url.url!)
        routeCache[key] = data
        return data
    }

    static func routes(near place: TrailPlace, radius: Int) async throws -> [HikingRoute] {
        let localRoutes = await DomesticRouteCatalog.shared.routes(near: place.point, radius: radius)
        let deltaLat = Double(radius) / 111.32
        let deltaLon = deltaLat / max(0.1, cos(place.point.lat * .pi / 180))
        func projected(_ lon: Double, _ lat: Double) -> [Double] {
            [
                max(-180, min(180, lon)) * 20037508.34 / 180,
                log(tan(.pi / 4 + max(-85, min(85, lat)) * .pi / 360)) * 6_378_137,
            ]
        }
        let bounds =
            projected(place.point.lon - deltaLon, place.point.lat - deltaLat)
            + projected(place.point.lon + deltaLon, place.point.lat + deltaLat)
        do {
            let data = try await routeData(
                "/list/by_area",
                items: [
                    URLQueryItem(name: "bbox", value: bounds.map { String($0) }.joined(separator: ",")),
                    URLQueryItem(name: "limit", value: "50"),
                ])
            return merge(localRoutes, try summaries(data, area: place.name, point: place.point))
        } catch {
            if !localRoutes.isEmpty { return localRoutes }
            throw error
        }
    }

    static func namedRoutes(_ query: String) async throws -> [HikingRoute] {
        let localRoutes = await DomesticRouteCatalog.shared.search(query)
        do {
            let data = try await routeData(
                "/list/search",
                items: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: "50")])
            let routes = try summaries(data, area: "按路线名称搜索", point: TrailPoint(lat: 0, lon: 0))
            return merge(localRoutes, routes.filter { matchesRouteName($0.name, query: query) })
        } catch {
            if !localRoutes.isEmpty { return localRoutes }
            throw error
        }
    }
    private static func merge(_ local: [HikingRoute], _ online: [HikingRoute]) -> [HikingRoute] {
        var seen = Set<Int64>()
        return (local + online).filter { seen.insert($0.id).inserted }
    }
    nonisolated static func matchesRouteName(_ name: String, query: String) -> Bool {
        func normalize(_ value: String) -> String {
            String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let needle = normalize(query)
        guard !needle.isEmpty else { return false }
        return normalize(name).contains(needle)
    }
    private static func summaries(_ data: Data, area: String, point: TrailPoint) throws -> [HikingRoute] {
        let response = try JSONDecoder().decode(RouteListResponse.self, from: data)
        return response.results.map {
            HikingRoute(
                id: $0.id, name: $0.name ?? $0.ref ?? "未命名徒步路线 #\($0.id)", area: area, center: point, distance: "")
        }
    }

    static func details(_ route: HikingRoute) async throws -> HikingRoute {
        let data = try await routeData("/details/relation/\(route.id)")
        return try decodeRoute(data, summary: route)
    }
    static func decodeRoute(_ data: Data, summary: HikingRoute) throws -> HikingRoute {
        let response = try JSONDecoder().decode(RouteDetails.self, from: data)
        guard response.bbox.count == 4 else { throw failure("这条路线缺少位置信息。") }
        let center = unproject(
            x: (response.bbox[0] + response.bbox[2]) / 2, y: (response.bbox[1] + response.bbox[3]) / 2)
        let length = response.official_length ?? response.route.length
        let distance =
            length.map {
                ($0 / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
                    + (response.official_length == nil ? "（地图估算）" : "（来源标注）")
            } ?? ""
        let segments = response.route.segments
        let route = HikingRoute(
            id: summary.id, name: response.tags?["name:zh"] ?? response.name ?? summary.name, area: summary.area,
            center: center, distance: distance, segments: segments,
            elevationProfile: summary.elevationProfile, elevationStats: summary.elevationStats)
        guard route.isValid else { throw failure("这条路线的轨迹过大或无效，无法保存。") }
        return route
    }
    nonisolated private static func unproject(x: Double, y: Double) -> TrailPoint {
        TrailPoint(lat: (2 * atan(exp(y / 6_378_137)) - .pi / 2) * 180 / .pi, lon: x / 20037508.34 * 180)
    }

    static func terrain(_ route: HikingRoute) async throws -> RouteTerrain? {
        if let recorded = RouteTerrain.recorded(route) { return recorded }
        let points = route.segments.flatMap { $0 }
        guard !points.isEmpty else { return nil }
        let count = min(100, points.count)
        let samples = (0..<count).map { points[$0 * (points.count - 1) / max(1, count - 1)] }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: samples.map { String($0.lat) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: samples.map { String($0.lon) }.joined(separator: ",")),
        ]
        struct Response: Decodable { let elevation: [Double] }
        let heights = try JSONDecoder().decode(Response.self, from: await TripHTTPClient.request(url.url!)).elevation
        guard heights.count == count, heights.allSatisfy(\.isFinite), let low = heights.min(), let high = heights.max()
        else { throw failure("海拔数据不完整。") }
        return RouteTerrain(
            low: low, high: high, average: heights.reduce(0, +) / Double(heights.count), ascent: nil, descent: nil,
            source: "Open-Meteo / Copernicus DEM 90 m，沿线采样海拔估算；累计爬升需含高程的连续轨迹")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private struct RouteListResponse: Decodable {
        let results: [Summary]
        struct Summary: Decodable {
            let id: Int64
            let name: String?
            let ref: String?
        }
    }
    private struct RouteDetails: Decodable {
        let name: String?
        let bbox: [Double]
        let official_length: Double?
        let tags: [String: String]?
        let route: RouteNode
    }
    private struct RouteNode: Decodable {
        let length: Double?
        let geometry: Geometry?
        let main: [RouteNode]?
        let ways: [RouteNode]?
        let appendices: [RouteNode]?
        var segments: [[TrailPoint]] {
            var result: [[TrailPoint]] = []
            if let geometry, geometry.type == "LineString" {
                let points = geometry.coordinates.compactMap { pair -> TrailPoint? in
                    guard pair.count >= 2 else { return nil }
                    return TripService.unproject(x: pair[0], y: pair[1])
                }
                if points.count > 1 { result.append(points) }
            }
            for node in (main ?? []) + (ways ?? []) + (appendices ?? []) { result += node.segments }
            return result
        }
        struct Geometry: Decodable {
            let type: String
            let coordinates: [[Double]]
        }
    }
}

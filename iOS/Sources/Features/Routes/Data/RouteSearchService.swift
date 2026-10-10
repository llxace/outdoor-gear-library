import Foundation

protocol RouteSearchProviding {
    func search(_ query: String) async throws -> [RouteSnapshot]
    func details(for route: RouteSnapshot) async throws -> RouteSnapshot
}

struct WaymarkedRouteSearchService: RouteSearchProviding {
    private let base = URL(string: "https://hiking.waymarkedtrails.org/api/v1")!

    func search(_ query: String) async throws -> [RouteSnapshot] {
        var components = URLComponents(url: base.appendingPathComponent("list/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: "30")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        let result = try JSONDecoder().decode(RouteListResponse.self, from: data)
        return result.results.compactMap { row in
            let name = row.name ?? row.ref ?? "未命名路线 #\(row.id)"
            guard Self.matches(name, query: query) else { return nil }
            return RouteSnapshot(id: row.id, name: name, area: "在线路线", distance: "加载轨迹中…", center: RoutePoint(lat: 0, lon: 0), segments: [])
        }
    }

    func details(for route: RouteSnapshot) async throws -> RouteSnapshot {
        let url = base.appendingPathComponent("details/relation/\(route.id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        let details = try JSONDecoder().decode(RouteDetails.self, from: data)
        guard details.bbox.count == 4 else { throw failure("这条路线缺少位置信息。") }
        let center = unproject(x: (details.bbox[0] + details.bbox[2]) / 2, y: (details.bbox[1] + details.bbox[3]) / 2)
        let length = details.officialLength ?? details.route.length
        let distance = length.map { String(format: "%.1f km（地图估算）", $0 / 1000) } ?? ""
        let name = details.tags?["name:zh"] ?? details.name ?? route.name
        let segments = details.route.segments
        guard !segments.isEmpty, segments.reduce(0, { $0 + $1.count }) <= 50_000 else {
            throw failure("路线轨迹为空或超过 50,000 个点。")
        }
        return RouteSnapshot(id: route.id, name: name, area: route.area, distance: distance, center: center, segments: segments)
    }

    private static func matches(_ name: String, query: String) -> Bool {
        let normalize: (String) -> String = { value in
            String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let needle = normalize(query)
        return !needle.isEmpty && normalize(name).contains(needle)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw failure("在线路线服务暂时无法连接。")
        }
    }

    private func unproject(x: Double, y: Double) -> RoutePoint {
        RoutePoint(lat: (2 * atan(exp(y / 6_378_137)) - .pi / 2) * 180 / .pi, lon: x / 20_037_508.34 * 180)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "RouteSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private struct RouteListResponse: Decodable {
        let results: [Summary]
        struct Summary: Decodable { let id: Int64; let name: String?; let ref: String? }
    }
    private struct RouteDetails: Decodable {
        let name: String?
        let bbox: [Double]
        let officialLength: Double?
        let tags: [String: String]?
        let route: RouteNode
        enum CodingKeys: String, CodingKey { case name, bbox, tags, route; case officialLength = "official_length" }
    }
    private struct RouteNode: Decodable {
        let length: Double?
        let geometry: Geometry?
        let main: [RouteNode]?
        let ways: [RouteNode]?
        let appendices: [RouteNode]?
        var segments: [[RoutePoint]] {
            var result: [[RoutePoint]] = []
            if let geometry, geometry.type == "LineString" {
                let points = geometry.coordinates.compactMap { pair -> RoutePoint? in
                    guard pair.count >= 2 else { return nil }
                    return RoutePoint(lat: (2 * atan(exp(pair[1] / 6_378_137)) - .pi / 2) * 180 / .pi,
                                      lon: pair[0] / 20_037_508.34 * 180)
                }
                if points.count > 1 { result.append(points) }
            }
            for child in (main ?? []) + (ways ?? []) + (appendices ?? []) { result += child.segments }
            return result
        }
        struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
    }
}

import Foundation

struct HikingRoute: Codable, Identifiable, Equatable {
    let id: Int64
    let name: String
    let area: String
    let center: TrailPoint
    let distance: String
    var segments: [[TrailPoint]] = []
    var elevationProfile: [RouteElevationSample]? = nil
    var elevationStats: RouteElevationStats? = nil
    var destinationOnly: Bool?
    var importedFile: String?
    var selectedSectionCount: Int? = nil
    var sourceURL: URL {
        if destinationOnly == true || importedFile != nil {
            var url = URLComponents(string: "https://maps.apple.com/")!
            url.queryItems = [
                URLQueryItem(name: "ll", value: "\(center.lat),\(center.lon)"), URLQueryItem(name: "q", value: name),
            ]
            return url.url!
        }
        return URL(string: "https://www.openstreetmap.org/relation/\(id)")!
    }
    var isValid: Bool {
        id > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && center.isValid
            && segments.reduce(0) { $0 + $1.count } <= 50000 && segments.allSatisfy { $0.allSatisfy(\.isValid) }
    }

    static func combining(_ routes: [HikingRoute]) -> HikingRoute? {
        guard !routes.isEmpty, routes.allSatisfy({ !$0.segments.isEmpty }) else { return nil }
        let segments = routes.flatMap(\.segments)
        let points = segments.flatMap { $0 }
        guard points.count <= 20000 else { return nil }
        let center = TrailPoint(
            lat: (points.map(\.lat).min()! + points.map(\.lat).max()!) / 2,
            lon: (points.map(\.lon).min()! + points.map(\.lon).max()!) / 2)
        let length = routes.reduce(0.0) { $0 + routeLength($1) }
        let distance = (length / 1000).formatted(.number.precision(.fractionLength(1))) + " km（所选路段合计）"
        let name = combinedName(routes)
        let stats = combinedStats(routes)
        var offset = 0.0
        let profile = routes.flatMap { route -> [RouteElevationSample] in
            let samples = (route.elevationProfile ?? []).map {
                RouteElevationSample(
                    distanceMeters: offset + $0.distanceMeters, lat: $0.lat, lon: $0.lon,
                    elevationMeters: $0.elevationMeters)
            }
            offset += route.elevationStats?.profileDistanceMeters ?? trackLength(route.segments)
            return samples
        }
        return HikingRoute(
            id: routes[0].id, name: name, area: routes[0].area, center: center, distance: distance,
            segments: segments, elevationProfile: profile.isEmpty ? nil : profile, elevationStats: stats,
            importedFile: "组合路线", selectedSectionCount: routes.count)
    }

    private static func combinedName(_ routes: [HikingRoute]) -> String {
        guard routes.count > 1 else { return routes[0].name }
        let prefix = routes[0].name.replacingOccurrences(of: #"第\d+段$"#, with: "", options: .regularExpression)
        let sameRoute = routes.allSatisfy { $0.name.hasPrefix(prefix) }
        return (sameRoute ? prefix : "自定义路线") + "（已选 \(routes.count) 段）"
    }

    private static func combinedStats(_ routes: [HikingRoute]) -> RouteElevationStats? {
        let values = routes.compactMap(\.elevationStats)
        guard values.count == routes.count else { return nil }
        let totalDistance = values.reduce(0) { $0 + $1.profileDistanceMeters }
        let sampleCount = values.reduce(0) { $0 + $1.profileSampleCount }
        guard totalDistance > 0, sampleCount > 0 else { return nil }
        return RouteElevationStats(
            minimumMeters: values.map(\.minimumMeters).min()!,
            maximumMeters: values.map(\.maximumMeters).max()!,
            averageMeters: values.reduce(0) { $0 + $1.averageMeters * $1.profileDistanceMeters } / totalDistance,
            estimatedAscentMeters: values.reduce(0) { $0 + $1.estimatedAscentMeters },
            estimatedDescentMeters: values.reduce(0) { $0 + $1.estimatedDescentMeters },
            profileDistanceMeters: totalDistance, profileSampleCount: sampleCount,
            noiseThresholdMeters: values.map(\.noiseThresholdMeters).max()!,
            source: Array(Set(values.map(\.source))).sorted().joined(separator: " / "),
            sourceResolutionMeters: values.map(\.sourceResolutionMeters).max()!,
            method: "分段海拔统计合计；平均海拔按分段距离加权")
    }

    private static func trackLength(_ segments: [[TrailPoint]]) -> Double {
        segments.reduce(0) { total, segment in
            total
                + zip(segment, segment.dropFirst()).reduce(0) { distance, pair in
                    let (a, b) = pair
                    let lat1 = a.lat * .pi / 180
                    let lat2 = b.lat * .pi / 180
                    let h =
                        pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2)
                        * pow(sin((b.lon - a.lon) * .pi / 360), 2)
                    return distance + 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, h))))
                }
        }
    }

    private static func routeLength(_ route: HikingRoute) -> Double {
        let label = route.distance.split(separator: "（").first.map(String.init) ?? ""
        let parts = label.split(whereSeparator: \.isWhitespace)
        if let value = parts.first.flatMap({ Double($0) }), let unit = parts.dropFirst().first {
            if unit.lowercased().hasPrefix("km") { return value * 1000 }
            if unit.lowercased().hasPrefix("m") { return value }
        }
        return route.elevationStats?.profileDistanceMeters ?? trackLength(route.segments)
    }
}

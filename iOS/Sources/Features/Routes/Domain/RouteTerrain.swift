import Foundation

struct RouteTerrain {
    let low: Double
    let high: Double
    let average: Double?
    let ascent: Double?
    let descent: Double?
    let source: String
    static func recorded(_ route: HikingRoute) -> RouteTerrain? {
        if let stats = route.elevationStats {
            return RouteTerrain(
                low: stats.minimumMeters, high: stats.maximumMeters, average: stats.averageMeters,
                ascent: stats.estimatedAscentMeters, descent: stats.estimatedDescentMeters, source: stats.source)
        }
        let points = route.segments.flatMap { $0 }
        guard !points.isEmpty, points.allSatisfy({ $0.elevation != nil }) else { return nil }
        let heights = points.compactMap(\.elevation)
        var up = 0.0
        var down = 0.0
        for segment in route.segments {
            for (a, b) in zip(segment, segment.dropFirst()) {
                let change = b.elevation! - a.elevation!
                up += max(0, change)
                down += max(0, -change)
            }
        }
        return RouteTerrain(
            low: heights.min()!, high: heights.max()!, average: heights.reduce(0, +) / Double(heights.count),
            ascent: up, descent: down, source: "轨迹文件高程，累计升降未去噪")
    }
}

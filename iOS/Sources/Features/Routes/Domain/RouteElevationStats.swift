import Foundation

struct RouteElevationStats: Codable, Equatable {
    let minimumMeters: Double
    let maximumMeters: Double
    let averageMeters: Double
    let estimatedAscentMeters: Double
    let estimatedDescentMeters: Double
    let profileDistanceMeters: Double
    let profileSampleCount: Int
    let noiseThresholdMeters: Double
    let source: String
    let sourceResolutionMeters: Double
    let method: String
}

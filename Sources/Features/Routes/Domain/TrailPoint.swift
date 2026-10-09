import Foundation

struct TrailPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    var elevation: Double?
    var isValid: Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
            && (elevation == nil || elevation!.isFinite)
    }
}

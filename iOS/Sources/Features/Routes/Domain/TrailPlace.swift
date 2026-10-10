import Foundation

struct TrailPlace: Identifiable {
    let id = UUID()
    let name: String
    let point: TrailPoint
}

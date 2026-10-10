import Foundation

struct Distribution: Identifiable {
    var id: String { name }
    let name: String
    let value: Double
}

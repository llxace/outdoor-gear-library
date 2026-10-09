import Foundation

struct PackingItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var quantity = 1.0
    var sourceGearID: UUID
    var isValid: Bool { quantity.isFinite && quantity > 0 }
}

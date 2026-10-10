import Foundation

struct PackingEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var quantity = 1.0
    var sourceGearID: UUID
}

struct BorrowedPackingEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var ownerID: UUID
    var ownerName: String
    var gear: Gear
    var quantity: Double
    var unavailable = false
    var subcategory: String?
}

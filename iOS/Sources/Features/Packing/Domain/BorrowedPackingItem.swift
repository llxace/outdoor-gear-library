import Foundation

struct BorrowedPackingItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let ownerID: UUID
    var ownerName: String
    var gear: Gear
    var quantity: Double
    var unavailable = false
    var subcategory: String?
    var isValid: Bool {
        (unavailable || gear.status != "损坏") && quantity.isFinite && quantity > 0 && quantity <= gear.quantity
            && gear.quantity.isFinite
            && gear.quantity > 0 && gear.weight.isFinite && gear.weight >= 0 && !gear.name.isEmpty
    }
}

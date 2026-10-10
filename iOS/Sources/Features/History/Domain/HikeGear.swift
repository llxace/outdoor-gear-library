import Foundation

struct HikeGear: Codable, Identifiable, Equatable {
    var id = UUID()
    var gear: Gear
    var quantity: Double
    var ownerName: String?
    var isValid: Bool {
        quantity.isFinite && quantity > 0 && gear.weight.isFinite && gear.weight >= 0
            && !gear.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

import Foundation

struct Gear: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var brand = ""
    var model = ""
    var category = "洗漱与杂项"
    var location = ""
    var quantity = 1.0
    var weight = 0.0
    var status = "可用"
    var purchasePrice = 0.0
    var purchaseFrom = ""
    var purchaseDate = ""
    var tags = ""
    var notes = ""
    var photo: String?
    var trashed = false
}

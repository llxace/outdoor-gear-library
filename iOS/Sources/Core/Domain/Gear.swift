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
    var trashed = false
    var photo: String?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, model, category, location, quantity, weight, status
        case purchasePrice, purchaseFrom, purchaseDate, tags, notes, trashed, photo
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try values.decodeIfPresent(String.self, forKey: .brand) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? ""
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "洗漱与杂项"
        location = try values.decodeIfPresent(String.self, forKey: .location) ?? ""
        quantity = try values.decodeIfPresent(Double.self, forKey: .quantity) ?? 1
        weight = try values.decodeIfPresent(Double.self, forKey: .weight) ?? 0
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "可用"
        purchasePrice = try values.decodeIfPresent(Double.self, forKey: .purchasePrice) ?? 0
        purchaseFrom = try values.decodeIfPresent(String.self, forKey: .purchaseFrom) ?? ""
        purchaseDate = try values.decodeIfPresent(String.self, forKey: .purchaseDate) ?? ""
        tags = try values.decodeIfPresent(String.self, forKey: .tags) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        trashed = try values.decodeIfPresent(Bool.self, forKey: .trashed) ?? false
        photo = try values.decodeIfPresent(String.self, forKey: .photo)
    }
}

import Foundation

enum PackingError: LocalizedError {
    case invalidQuantity
    case damagedGear
    case exceedsStock(String, Double)

    var errorDescription: String? {
        switch self {
        case .invalidQuantity: "携带数量须大于 0。"
        case .damagedGear: "已损坏的装备不能加入打包清单。"
        case let .exceedsStock(name, stock): "“\(name)”库存为 \(stock.formatted()) 件，携带数量不能超过库存。"
        }
    }
}

enum PackingOperations {
    static func setQuantity(_ quantity: Double?, for gear: Gear, in rows: [[String: Any]]) throws -> [[String: Any]] {
        guard let quantity else {
            return rows.filter { ($0["sourceGearID"] as? String).flatMap(UUID.init(uuidString:)) != gear.id }
        }
        guard quantity.isFinite, quantity > 0 else { throw PackingError.invalidQuantity }
        guard gear.status != "损坏" else { throw PackingError.damagedGear }
        guard quantity <= gear.quantity else { throw PackingError.exceedsStock(gear.name, gear.quantity) }
        if let index = rows.firstIndex(where: { ($0["sourceGearID"] as? String).flatMap(UUID.init(uuidString:)) == gear.id }) {
            var updated = rows
            updated[index]["quantity"] = quantity
            return updated
        }
        return rows + [["id": UUID().uuidString, "quantity": quantity, "sourceGearID": gear.id.uuidString]]
    }

    static func updateBorrowedQuantity(_ quantity: Double, for id: UUID, in rows: [[String: Any]]) throws -> [[String: Any]] {
        guard quantity.isFinite, quantity > 0,
              let index = rows.firstIndex(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == id }),
              let gear = rows[index]["gear"] as? [String: Any],
              let stock = gear["quantity"] as? Double else { throw PackingError.invalidQuantity }
        guard quantity <= stock else {
            throw PackingError.exceedsStock(gear["name"] as? String ?? "装备", stock)
        }
        var updated = rows
        updated[index]["quantity"] = quantity
        return updated
    }
}

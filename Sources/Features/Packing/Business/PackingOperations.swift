import Foundation

enum PackingOperations {
    static func setPackingQuantity(_ quantity: Double?, for id: UUID, in inventory: Inventory) throws -> Inventory {
        let items = inventory.items.filter { !$0.trashed }
        var next = inventory
        next.packingItems.removeAll { $0.sourceGearID == id }
        if let quantity {
            guard let gear = items.first(where: { $0.id == id }), quantity.isFinite, quantity > 0 else {
                throw BusinessError("携带数量须大于 0。")
            }
            guard gear.status != "损坏" else { throw BusinessError("已损坏的装备不能加入打包清单。") }
            guard quantity <= gear.quantity else {
                throw BusinessError("“\(gear.name)”录入了 \(gear.quantity.formatted()) 件，携带数量不能超过这个数量。")
            }
            next.packingItems.append(PackingItem(quantity: quantity, sourceGearID: id))
        }
        return next
    }

    static func removeUnavailablePackingItems(in inventory: Inventory) throws -> Inventory {
        let items = inventory.items.filter { !$0.trashed }
        var next = inventory
        let available = Set(items.map(\.id))
        next.packingItems.removeAll { !available.contains($0.sourceGearID) }
        next.borrowedPackingItems.removeAll { $0.unavailable }
        return next
    }
}

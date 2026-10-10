import Foundation

enum BorrowingOperations {
    static func setBorrowedQuantity(_ quantity: Double?, item: BorrowedPackingItem, in inventory: Inventory) throws
        -> Inventory
    {
        var next = inventory
        next.borrowedPackingItems.removeAll { $0.ownerID == item.ownerID && $0.gear.id == item.gear.id }
        if let quantity {
            guard item.gear.status != "损坏" else { throw BusinessError("已损坏的装备不能加入打包清单。") }
            guard quantity.isFinite, quantity > 0, quantity <= item.gear.quantity else {
                throw BusinessError("携带数量不能超过来源库的数量。")
            }
            var updated = item
            updated.quantity = quantity
            next.borrowedPackingItems.append(updated)
        }
        return next
    }

    static func restoreClearedPacking(own: [PackingItem], borrowed: [BorrowedPackingItem], in inventory: Inventory)
        throws -> Inventory
    {
        var next = inventory
        next.packingItems += own.filter { saved in !next.packingItems.contains { $0.sourceGearID == saved.sourceGearID }
        }
        next.borrowedPackingItems += borrowed.filter { saved in
            !next.borrowedPackingItems.contains { $0.ownerID == saved.ownerID && $0.gear.id == saved.gear.id }
        }
        return next
    }
}

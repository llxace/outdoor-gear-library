import Foundation

extension GearStore {
    @discardableResult func setBorrowedQuantity(_ quantity: Double?, item: BorrowedPackingItem) -> Bool {
        return updateInventory { try BorrowingOperations.setBorrowedQuantity(quantity, item: item, in: $0) }
    }
    @discardableResult func restoreClearedPacking(own: [PackingItem], borrowed: [BorrowedPackingItem]) -> Bool {
        return updateInventory { try BorrowingOperations.restoreClearedPacking(own: own, borrowed: borrowed, in: $0) }
    }
    @discardableResult func clearPackingList() -> Bool {
        var next = inventory
        next.packingItems = []
        next.borrowedPackingItems = []
        return commit(next)
    }
}

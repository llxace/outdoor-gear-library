import Foundation

extension GearStore {
    @discardableResult func setPackingQuantity(_ quantity: Double?, for id: UUID) -> Bool {
        return updateInventory { try PackingOperations.setPackingQuantity(quantity, for: id, in: $0) }
    }
    func removeUnavailablePackingItems() {
        _ = updateInventory { try PackingOperations.removeUnavailablePackingItems(in: $0) }
    }
}

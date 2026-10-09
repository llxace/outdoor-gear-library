import Foundation

extension GearStore {
    func hikeFromPacking() -> HikeRecord {
        var record = HikeRecord()
        record.mealPlan = inventory.mealPlan
        record.route = inventory.selectedRoute
        record.routeName = record.route?.name ?? ""
        record.title = record.routeName.isEmpty ? "徒步记录" : record.routeName
        record.distance = record.route?.distance ?? ""
        record.gear = inventory.packingGear.map { HikeGear(gear: $0, quantity: inventory.packingQuantity($0.id) ?? 1) }
        record.gear += inventory.borrowedPackingItems.filter { !$0.unavailable }.map {
            HikeGear(gear: $0.gear, quantity: $0.quantity, ownerName: $0.ownerName)
        }
        return record
    }
    @discardableResult func saveHike(_ record: HikeRecord) -> Bool {
        return updateInventory { try HistoryOperations.saveHike(record, in: $0) }
    }
}

import Foundation

enum HistoryOperations {
    static func saveHike(_ record: HikeRecord, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.hikeHistory.removeAll { $0.id == record.id }
        next.hikeHistory.append(record)
        return next
    }
}

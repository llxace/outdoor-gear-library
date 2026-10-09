import Foundation

extension Inventory {
    func validateRelationships() throws {
        guard mealPlan.isValid else { throw CocoaError(.fileReadCorruptFile) }
        guard hikeHistory.allSatisfy(\.isValid), Set(hikeHistory.map(\.id)).count == hikeHistory.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard borrowedPackingItems.allSatisfy(\.isValid),
            Set(borrowedPackingItems.map { $0.ownerID.uuidString + $0.gear.id.uuidString }).count
                == borrowedPackingItems.count
        else { throw CocoaError(.fileReadCorruptFile) }
        if let route = selectedRoute, !route.isValid { throw CocoaError(.fileReadCorruptFile) }
        guard Set(packingItems.map(\.id)).count == packingItems.count,
            packingItems.allSatisfy({ $0.isValid })
                && Set(packingItems.map(\.sourceGearID)).count == packingItems.count, packingWeight.isFinite
        else { throw CocoaError(.fileReadCorruptFile) }
        try validateGearRelationships()
    }
    private func validateGearRelationships() throws {
        let ids = Set(gear.map(\.id))
        guard ids.count == gear.count else { throw CocoaError(.fileReadCorruptFile) }
        for record in gear {
            guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                record.quantity.isFinite, record.quantity > 0,
                [record.weight, record.purchasePrice].allSatisfy({ $0.isFinite && $0 >= 0 })
            else { throw CocoaError(.fileReadCorruptFile) }
            let detail = extras(record.id)
            if let parent = detail.parentID {
                guard ids.contains(parent), parent != record.id, !descendants(of: record.id).contains(parent),
                    !detail.isLocation || extras(parent).isLocation
                else { throw CocoaError(.fileReadCorruptFile) }
            }
            if let location = detail.locationOverrideID {
                guard ids.contains(location), extras(location).isLocation else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
    }
}

import Foundation

enum BackupMerge {
    static func restoring(_ backup: Inventory, into inventory: Inventory) throws -> Inventory {
        var next = inventory
        let restoredIDs = Set(backup.gear.map(\.id))
        next.gear.removeAll { restoredIDs.contains($0.id) }
        next.gear += backup.gear
        let packingIDs = Set(backup.packingItems.map(\.id))
        next.packingItems.removeAll { packingIDs.contains($0.id) }
        next.packingItems += backup.packingItems
        for item in backup.borrowedPackingItems {
            next.borrowedPackingItems.removeAll { $0.ownerID == item.ownerID && $0.gear.id == item.gear.id }
            next.borrowedPackingItems.append(item)
        }
        if backup.version >= 9 { next.mealPlan = backup.mealPlan }
        let historyIDs = Set(backup.hikeHistory.map(\.id))
        next.hikeHistory.removeAll { historyIDs.contains($0.id) }
        next.hikeHistory += backup.hikeHistory
        next.details.merge(backup.details) { _, restored in restored }
        mergeLabels(from: backup, into: &next)
        mergeTemplates(from: backup, into: &next)
        resolveAssetIdentifiers(in: &next, restoredIDs: restoredIDs)
        next.locations = next.places.map(\.name)
        if let route = backup.selectedRoute { next.selectedRoute = route }
        next.settings = backup.settings
        try next.validateRelationships()
        return next
    }

    private static func mergeLabels(from backup: Inventory, into next: inout Inventory) {
        for restored in backup.labels {
            if let old = next.labels.first(where: { $0.name == restored.name && $0.id != restored.id }) {
                for i in next.labels.indices where next.labels[i].parentID == old.id {
                    next.labels[i].parentID = restored.id
                }
                next.labels.removeAll { $0.id == old.id }
            }
            next.labels.removeAll { $0.id == restored.id }
            next.labels.append(restored)
        }
    }

    private static func mergeTemplates(from backup: Inventory, into next: inout Inventory) {
        for restored in backup.templates {
            next.templates.removeAll { $0.id == restored.id }
            next.templates.append(restored)
        }
    }

    private static func resolveAssetIdentifiers(in next: inout Inventory, restoredIDs: Set<UUID>) {
        var used: Set<Int> = []
        let maxAsset = next.details.values.map(\.assetID).max() ?? 0
        var nextAsset = maxAsset + 1
        for record in next.gear.sorted(by: { restoredIDs.contains($0.id) && !restoredIDs.contains($1.id) }) {
            var detail = next.extras(record.id)
            if detail.assetID <= 0 || used.contains(detail.assetID) {
                detail.assetID = nextAsset
                nextAsset += 1
            }
            used.insert(detail.assetID)
            next.details[record.id.uuidString] = detail
        }
    }
}

import Foundation

extension GearLibrary {
    func saveGear(_ gear: Gear) {
        var rows = inventory["gear"] as? [[String: Any]] ?? []
        let encoded = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(gear))) as? [String: Any] ?? [:]
        if let index = rows.firstIndex(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == gear.id }) {
            rows[index].merge(encoded) { _, new in new }
        } else {
            rows.insert(encoded, at: 0)
        }
        inventory["gear"] = rows
        save()
    }

    func moveToTrash(_ gear: Gear) {
        var item = gear
        item.trashed = true
        saveGear(item)
    }

    func restore(_ gear: Gear) {
        var item = gear
        item.trashed = false
        saveGear(item)
    }

    func deletePermanently(_ gear: Gear) {
        var rows = inventory["gear"] as? [[String: Any]] ?? []
        rows.removeAll { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == gear.id }
        inventory["gear"] = rows
        let packed = inventory["packingItems"] as? [[String: Any]] ?? []
        inventory["packingItems"] = packed.filter { ($0["sourceGearID"] as? String).flatMap(UUID.init(uuidString:)) != gear.id }
        save()
    }
}

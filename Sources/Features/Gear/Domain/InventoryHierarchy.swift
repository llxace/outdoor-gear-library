import Foundation

extension Inventory {
    func extras(_ id: UUID) -> GearExtras { details[id.uuidString] ?? GearExtras() }
    func children(of id: UUID) -> [Gear] { gear.filter { extras($0.id).parentID == id && !$0.trashed } }
    func descendants(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var queue = [id]
        while let parent = queue.popLast() {
            for child in gear.filter({ extras($0.id).parentID == parent })
            where !result.contains(child.id) && child.id != id {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }
    func path(_ id: UUID) -> String {
        var names: [String] = []
        var cursor: UUID? = id
        var visited: Set<UUID> = []
        while let current = cursor, !visited.contains(current), let record = gear.first(where: { $0.id == current }) {
            names.insert(record.name, at: 0)
            visited.insert(current)
            cursor = extras(current).parentID
        }
        return names.joined(separator: " / ")
    }
    func location(for id: UUID) -> String {
        if let location = locationID(for: id) { return path(location) }
        return gear.first(where: { $0.id == id })?.location ?? ""
    }
    func locationID(for id: UUID) -> UUID? {
        let detail = extras(id)
        if let override = detail.locationOverrideID { return override }
        var cursor = detail.parentID
        var visited: Set<UUID> = []
        while let current = cursor, !visited.contains(current) {
            visited.insert(current)
            if extras(current).isLocation { return current }
            if let override = extras(current).locationOverrideID { return override }
            cursor = extras(current).parentID
        }
        return nil
    }
    var items: [Gear] { gear.filter { !extras($0.id).isLocation } }
    var places: [Gear] { gear.filter { extras($0.id).isLocation && !$0.trashed } }

    mutating func migrateNativeV1() {
        if labels.isEmpty {
            labels = categories.map { GearTag(name: $0) }
        }
        for name in locations where !places.contains(where: { $0.name == name }) {
            var place = Gear()
            place.name = name
            place.category = "位置"
            var detail = GearExtras()
            detail.isLocation = true
            gear.append(place)
            details[place.id.uuidString] = detail
        }
        for record in gear {
            var detail = extras(record.id)
            if detail.assetID == 0 { detail.assetID = (details.values.map(\.assetID).max() ?? 0) + 1 }
            if detail.importRef.isEmpty { detail.importRef = record.id.uuidString }
            if detail.parentID == nil && !detail.isLocation && !record.location.isEmpty {
                detail.parentID = places.first { $0.name == record.location }?.id
            }
            details[record.id.uuidString] = detail
        }
    }
}

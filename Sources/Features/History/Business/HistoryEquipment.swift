import Foundation

enum HistoryEquipment {
    static func category(_ gear: Gear) -> String {
        let value = gear.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未分类" : value
    }

    static func categories(_ gear: [Gear]) -> [String] {
        Set(gear.map { category($0) }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func matches(_ gear: Gear, search: String, category selected: String?) -> Bool {
        guard selected == nil || category(gear) == selected else { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || [gear.name, gear.brand, gear.model, category(gear), gear.tags, gear.notes]
                .contains { $0.localizedStandardContains(query) }
    }

    static func adding(_ additions: [HikeGear], to existing: [HikeGear]) -> [HikeGear] {
        var result = existing
        for item in additions {
            guard !result.contains(where: { $0.gear.id == item.gear.id && $0.ownerName == item.ownerName }) else {
                continue
            }
            var snapshot = item
            snapshot.id = UUID()
            result.append(snapshot)
        }
        return result
    }

    static func weight(_ items: [HikeGear]) -> Double {
        items.reduce(0) { $0 + $1.gear.weight * $1.quantity }
    }
}

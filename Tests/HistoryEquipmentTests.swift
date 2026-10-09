import Foundation

@main struct HistoryEquipmentChecks {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw NSError(domain: "HistoryEquipmentChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        assertions += 1
    }
    static func main() throws {
        try queries()
        try snapshots()
        try persistence()
        print("PASS: \(assertions) assertions; history search/category, deduplication, independent snapshots and persistence")
    }
    static func sample() -> Gear {
        var gear = Gear()
        gear.name = "睡袋"; gear.category = "睡眠系统"; gear.brand = "黑冰"; gear.model = "G700"
        gear.tags = "保暖"; gear.notes = "夜间舒适"; gear.weight = 700; gear.quantity = 1
        return gear
    }
    static func queries() throws {
        let gear = sample()
        for query in ["睡袋", "黑冰", "g700", "睡眠", "保暖", "舒适", "  G700  ", ""] {
            try expect(HistoryEquipment.matches(gear, search: query, category: nil), "search \(query)")
        }
        try expect(!HistoryEquipment.matches(gear, search: "帐篷", category: nil), "unmatched search")
        try expect(!HistoryEquipment.matches(gear, search: "", category: "炊事"), "different category excluded")
        try expect(HistoryEquipment.matches(gear, search: "黑冰", category: "睡眠系统"), "combined filters")
        var blank = Gear(); blank.category = "   "
        try expect(HistoryEquipment.category(blank) == "未分类", "empty category fallback")
        try expect(Set(HistoryEquipment.categories([gear, gear, blank])) == ["睡眠系统", "未分类"], "unique categories")
    }
    static func snapshots() throws {
        let gear = sample()
        let own = HikeGear(gear: gear, quantity: 2)
        let borrowed = HikeGear(gear: gear, quantity: 1, ownerName: "同伴")
        var result = HistoryEquipment.adding([own, own, borrowed], to: [])
        try expect(result.count == 2, "dedup within incoming batch; preserve different owners")
        try expect(result[0].id != own.id && result[1].id != borrowed.id, "fresh historical row identities")
        try expect(HistoryEquipment.adding([own], to: result) == result, "existing snapshot not overwritten")
        try expect(HistoryEquipment.weight(result) == 2100, "quantity weighted total")
        result[0].gear.weight = 600; result[0].gear.notes = "当晚偏冷"; result[0].quantity = 3
        try expect(gear.weight == 700 && own.quantity == 2 && gear.notes == "夜间舒适", "source remains independent")
        try expect(result[0].isValid, "historical quantities may exceed current stock")
        result[0].gear.status = "损坏"
        try expect(result[0].isValid, "current damage does not invalidate past trip")
        result[0].quantity = 0
        try expect(!result[0].isValid, "zero quantity rejected")
        result[0].quantity = 1; result[0].gear.weight = -1
        try expect(!result[0].isValid, "negative weight rejected")
    }
    static func persistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryEquipment-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GearStore(root: root, seedInitialInventory: false)
        let gear = sample()
        try expect(store.save(gear), "save current inventory")
        var record = HikeRecord(); record.title = "历史验收"
        record.gear = HistoryEquipment.adding([HikeGear(gear: gear, quantity: 3)], to: [])
        record.gear[0].gear.notes = "当次反馈"; record.gear[0].gear.weight = 650
        try expect(store.saveHike(record), "save history")
        try expect(store.items.first?.weight == 700 && store.items.first?.notes == "夜间舒适", "history edits leave inventory intact")
        let reopened = GearStore(root: root, seedInitialInventory: false)
        try expect(reopened.inventory.hikeHistory.first == record, "historical fields persist")
        let backup = root.appendingPathComponent("验收备份")
        try store.backup(to: backup)
        let restored = GearStore(root: root.appendingPathComponent("restored"), seedInitialInventory: false)
        _ = try restored.restore(from: backup)
        try expect(restored.inventory.hikeHistory.first == record, "backup restores equipment snapshot")
    }
}

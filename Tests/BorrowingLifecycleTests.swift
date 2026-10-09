import Foundation

@main struct BorrowingLifecycleChecks {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw NSError(domain: "BorrowingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        assertions += 1
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BorrowingLifecycle-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let libraries = UserLibraries(root: root)
        let borrower = libraries.selectedID
        try expect(libraries.saveUser(name: "来源用户"), "create owner")
        let owner = libraries.selectedID
        let source = libraries.store
        var gear = Gear(); gear.name = "借用装备"; gear.quantity = 2; gear.weight = 100
        try expect(source.save(gear), "save owner gear")
        try expect(libraries.select(borrower), "switch borrower")
        let item = BorrowedPackingItem(ownerID: owner, ownerName: "来源用户", gear: gear, quantity: 2)
        try expect(libraries.store.setBorrowedQuantity(2, item: item), "borrow two")
        gear.quantity = 1; gear.weight = 120
        try expect(source.save(gear), "owner stock shrinks")
        libraries.refreshBorrowedPackingItems()
        try expect(libraries.store.inventory.packingWeight == 120, "borrow follows stock and weight")
        try expect(libraries.saveUser(name: "来源用户改名", renaming: owner), "rename owner")
        libraries.refreshBorrowedPackingItems()
        try expect(libraries.store.inventory.borrowedPackingItems[0].ownerName == "来源用户改名", "borrow follows owner name")
        gear.status = "损坏"; try expect(source.save(gear), "owner damages gear")
        libraries.refreshBorrowedPackingItems()
        try expect(libraries.store.inventory.borrowedPackingItems[0].unavailable, "damaged loan becomes unavailable")
        try expect(libraries.store.inventory.packingWeight == 0, "damaged loan excluded from weight")
        let reopened = GearStore(root: libraries.store.root, seedInitialInventory: false)
        try expect(reopened.ready && reopened.inventory.borrowedPackingItems[0].unavailable, "unavailable loan persists")
        gear.status = "可用"; try expect(source.save(gear), "owner repairs gear")
        libraries.refreshBorrowedPackingItems()
        try expect(!libraries.store.inventory.borrowedPackingItems[0].unavailable && libraries.store.inventory.packingWeight == 120, "repaired loan available again")
        try expect(source.changeRecords([gear.id], trash: true), "owner trashes gear")
        libraries.refreshBorrowedPackingItems()
        try expect(libraries.store.inventory.borrowedPackingItems[0].unavailable && libraries.store.inventory.packingWeight == 0, "missing source excluded")
        libraries.store.removeUnavailablePackingItems()
        try expect(libraries.store.inventory.borrowedPackingItems.isEmpty, "remove unavailable loan")
        print("PASS: \(assertions) assertions; borrowed stock/weight/name refresh, damage/repair, persistence, owner trash and cleanup")
    }
}

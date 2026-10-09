import Foundation
import AppKit

@main struct RefactorRegressionChecks {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw NSError(domain: "Regression", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        assertions += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        var rejected = false
        do { try operation() } catch { rejected = true }
        try expect(rejected, name)
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearRefactorAcceptance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try packingAndHistory(root.appendingPathComponent("packing"))
        try profiles(root.appendingPathComponent("profiles"))
        try mealsAndLabels()
        try tracksAndCSV()
        try backupSafety(root.appendingPathComponent("backup"))
        print("PASS: \(assertions) assertions; packing, quantities, damage, trash, borrowing, history snapshots, profile isolation, asset rollback, meals, OCR parsing, GPX/KML, CSV, backup and schema safety")
    }
    static func packingAndHistory(_ root: URL) throws {
        let store = GearStore(root: root, seedInitialInventory: false)
        var gear = Gear(); gear.name = "登山杖"; gear.quantity = 2; gear.weight = 210; gear.purchasePrice = 400
        try expect(store.save(gear), "save gear")
        try expect(store.setPackingQuantity(2, for: gear.id), "pack two")
        try expect(store.inventory.packingWeight == 420 && store.inventory.packingValue == 400, "weight and value")
        try expect(!store.setPackingQuantity(3, for: gear.id), "reject overstock")
        try expect(!store.setPackingQuantity(.nan, for: gear.id), "reject NaN")
        try expect(store.inventory.packingWeight == 420, "invalid edits preserve packing")
        gear.quantity = 1; try expect(store.save(gear), "stock shrink")
        try expect(store.inventory.packingQuantity(gear.id) == 1 && store.inventory.packingWeight == 210, "cap stock")
        let history = store.hikeFromPacking()
        try expect(store.saveHike(history), "save snapshot")
        gear.weight = 250; try expect(store.save(gear), "change gear weight")
        try expect(store.inventory.hikeHistory[0].weight == 210 && store.inventory.packingWeight == 250, "snapshot independent")
        gear.status = "损坏"; try expect(store.save(gear), "damage gear")
        try expect(store.inventory.packingItems.isEmpty && !store.setPackingQuantity(1, for: gear.id), "damaged exclusion")
        gear.status = "已购"; try expect(store.save(gear), "repair gear")
        try expect(store.setPackingQuantity(1, for: gear.id), "repack repaired")
        try expect(store.changeRecords([gear.id], trash: true), "trash")
        try expect(store.inventory.packingWeight == 0 && store.inventory.unavailablePackingItems == 1, "trashed exclusion")
        try expect(store.changeRecords([gear.id], trash: false), "restore")
        var other = Gear(); other.name = "借用水壶"; other.weight = 100; other.quantity = 2
        let borrowed = BorrowedPackingItem(ownerID: UUID(), ownerName: "伙伴", gear: other, quantity: 2)
        try expect(store.setBorrowedQuantity(2, item: borrowed), "borrow")
        try expect(store.inventory.packingWeight == 450, "borrowed weight")
        let own = store.inventory.packingItems; let loans = store.inventory.borrowedPackingItems
        try expect(store.clearPackingList() && store.inventory.packingWeight == 0, "clear")
        try expect(store.restoreClearedPacking(own: own, borrowed: loans), "undo clear")
        try expect(store.inventory.packingWeight == 450, "undo weight")
        let reopened = GearStore(root: root, seedInitialInventory: false)
        try expect(reopened.inventory.packingWeight == 450 && reopened.inventory.hikeHistory[0].weight == 210, "persistent packing and history")
    }
    static func profiles(_ root: URL) throws {
        let libraries = UserLibraries(root: root)
        try expect(libraries.ready, "profiles ready")
        let originalID = libraries.selectedID
        var gear = Gear(); gear.name = "默认用户帐篷"; gear.weight = 1000
        try expect(libraries.store.save(gear), "default inventory")
        let originalStore = libraries.store
        try expect(libraries.saveUser(name: "伙伴"), "create profile")
        let newID = libraries.selectedID
        try expect(newID != originalID && libraries.store.inventory.gear.isEmpty, "new profile empty")
        try expect(!libraries.saveUser(name: " 伙伴 "), "duplicate profile rejected")
        try expect(libraries.saveUser(name: "伙伴改名", renaming: newID), "rename profile")
        try expect(libraries.selectedID == newID, "rename keeps UUID")
        let fixture = Data("file fixture".utf8)
        try fixture.write(to: originalStore.photoURL("photo.png"))
        try fixture.write(to: originalStore.root.appendingPathComponent("Files/manual.txt"))
        gear.photo = "photo.png"
        var extras = GearExtras(); extras.parentID = UUID(); extras.assetID = 99; extras.importRef = "OLD"
        extras.attachments = [GearAttachment(title: "说明书", file: "manual.txt")]
        let (copy, detail) = try libraries.store.copyUnsavedGear(gear, extras: extras, from: originalStore)
        try expect(copy.photo != gear.photo && detail.parentID == nil && detail.assetID == 0 && detail.importRef.isEmpty, "cross-user identity cleanup")
        try expect(try Data(contentsOf: libraries.store.photoURL(copy.photo!)) == fixture, "cross-user photo bytes")
        try expect(libraries.store.save(copy, extras: detail), "save transferred draft")
        let photos = try FileManager.default.contentsOfDirectory(atPath: libraries.store.root.appendingPathComponent("Photos").path)
        extras.attachments = [GearAttachment(title: "失效附件", file: "missing.txt")]
        try rejects("transfer fails on missing attachment") { _ = try libraries.store.copyUnsavedGear(gear, extras: extras, from: originalStore) }
        let after = try FileManager.default.contentsOfDirectory(atPath: libraries.store.root.appendingPathComponent("Photos").path)
        try expect(Set(photos) == Set(after), "failed transfer rolls photo back")
        try expect(libraries.select(originalID), "switch to original")
        try expect(libraries.store.inventory.gear[0].photo == nil, "original inventory unchanged")
        let reopened = UserLibraries(root: root)
        try expect(reopened.selectedID == originalID && reopened.users.count == 2, "selected profile persisted")
        try expect(reopened.select(newID) && reopened.store.inventory.gear.count == 1, "second inventory persisted")
    }
    static func mealsAndLabels() throws {
        var options = TrailMealRecommendationOptions()
        options.days = 4; options.people = 2; options.resupply = true; options.startDay = 2; options.carryDays = 2
        let foods = options.foods()
        try expect(foods.count == 13 && Set(foods.map(\.day)) == [2, 3], "resupply day coverage and reserve")
        var plan = TrailMealPlan(); plan.days = 4; plan.people = 2; plan.foods = foods; plan.waterLiters = 2
        try expect(plan.isValid, "recommended plan valid")
        try expect(abs(plan.energy(day: 2) - 5000) < 0.001 && plan.totalWeight == plan.foodWeight + 2000, "calories and water units")
        options.days = 0; try expect(options.foods().isEmpty, "invalid recommendations rejected")
        let label = FoodLabelResult.parse("品名：燕麦\n净含量 200 g\n每100g 能量 418.4 kJ")
        try expect(label.name == "燕麦" && label.grams == 200 && abs((label.calories ?? 0) - 200) < 0.001, "OCR per100g kJ conversion")
        let ambiguous = FoodLabelResult.parse("净含量 1 kg\n能量 400 kcal")
        try expect(ambiguous.grams == 1000 && ambiguous.calories == nil, "ambiguous energy not auto-filled")
    }
    static func tracksAndCSV() throws {
        let gpx = "<gpx><trk><name>测试路线</name><trkseg><trkpt lat='39' lon='112'><ele>100</ele></trkpt><trkpt lat='39.01' lon='112'><ele>130</ele></trkpt></trkseg></trk></gpx>"
        let route = try TrailFileReader.read(Data(gpx.utf8), filename: "route.gpx")
        try expect(route.name == "测试路线" && route.segments[0].count == 2 && route.isValid, "GPX geometry")
        let terrain = RouteTerrain.recorded(route)
        try expect(terrain?.low == 100 && terrain?.high == 130 && terrain?.ascent == 30, "GPX elevation")
        let kml = "<kml><Document><name>KML路线</name><Placemark><LineString><coordinates>112,39,100 112,39.01,130</coordinates></LineString></Placemark></Document></kml>"
        let imported = try TrailFileReader.read(Data(kml.utf8), filename: "route.kml")
        try expect(imported.segments == route.segments && imported.distance == route.distance, "KML geometry equivalent")
        try rejects("invalid coordinates") { _ = try TrailFileReader.read(Data(gpx.replacingOccurrences(of: "lat='39'", with: "lat='999'").utf8), filename: "bad.gpx") }
        try rejects("waypoints alone") { _ = try TrailFileReader.read(Data("<gpx><wpt lat='39' lon='112'/></gpx>".utf8), filename: "waypoint.gpx") }
        let combined = HikingRoute.combining([route, imported])
        try expect(combined?.selectedSectionCount == 2 && combined?.segments.count == 2, "combine route sections")
        let cells = [["中文", "comma,quote\"", "line\r\nline"], ["空值", "", "末尾"]]
        try expect(try CSV.parse(CSV.encode(cells)) == cells, "CSV quoted multiline roundtrip")
        try expect(try CSV.parse("\u{FEFF}名称\t备注\r\n水壶\t\"a\tb\"\r\n", delimiter: "\t") == [["名称", "备注"], ["水壶", "a\tb"]], "TSV BOM CRLF quoted tabs")
    }
    static func backupSafety(_ root: URL) throws {
        let store = GearStore(root: root, seedInitialInventory: false)
        var gear = Gear(); gear.name = "备份装备"; gear.weight = 99
        try expect(store.save(gear) && store.setPackingQuantity(1, for: gear.id), "backup fixture")
        let snapshot = store.hikeFromPacking(); try expect(store.saveHike(snapshot), "backup history")
        let backup = root.appendingPathComponent("full.gearbackup")
        try store.backup(to: backup)
        try rejects("backup refuses overwrite") { try store.backup(to: backup) }
        let target = GearStore(root: root.appendingPathComponent("restored"), seedInitialInventory: false)
        try expect(try target.restore(from: backup), "restore backup")
        try expect(target.inventory.packingWeight == 99 && target.inventory.hikeHistory.count == 1, "restore packing and history")
        var invalid = store.inventory; invalid.gear[0].photo = "../escape.png"
        try JSONEncoder().encode(invalid).write(to: backup.appendingPathComponent("inventory.json"))
        let before = try Data(contentsOf: target.root.appendingPathComponent("inventory.json"))
        try rejects("backup traversal rejected") { _ = try target.restore(from: backup) }
        try expect(try Data(contentsOf: target.root.appendingPathComponent("inventory.json")) == before, "failed restore keeps inventory")
        invalid = store.inventory; invalid.version = 999
        try JSONEncoder().encode(invalid).write(to: root.appendingPathComponent("inventory.json"))
        let unsupported = GearStore(root: root, seedInitialInventory: false)
        try expect(!unsupported.ready && !unsupported.save(gear), "future schema not overwritten")
    }
}

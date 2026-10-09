import Foundation
import AppKit

@main struct Checks {
    static func main() throws {
        let multiline = [["名称", "备注"], ["帐篷,双人", "第一行\n第二行\"引用\""]]
        let parsed = try CSV.parse(CSV.encode(multiline))
        precondition(parsed == multiline)
        let imported = try NativeCSV.merge("HB.name,HB.quantity,HB.purchase_price\r\n睡垫,2,899.5\r\n", into: Inventory()).items
        precondition(imported.count == 1 && imported[0].quantity == 2)
        var invalidWasRejected = false
        do { _ = try NativeCSV.merge("名称,单件重量(g)\n头灯,-5", into: Inventory()) } catch { invalidWasRejected = true }
        precondition(invalidWasRejected)
        var brokenQuoteWasRejected = false
        do { _ = try CSV.parse("\"unfinished") } catch { brokenQuoteWasRejected = true }
        precondition(brokenQuoteWasRejected)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OutdoorGearTests-" + UUID().uuidString)
        let store = GearStore(root: root)
        precondition(store.ready)
        var gear = Gear()
        gear.name = "测试,头灯"; gear.weight = 83.5; gear.purchasePrice = 249
        gear.notes = "包含\n换行与\"引号\""
        precondition(store.save(gear))
        let reopened = GearStore(root: root)
        precondition(reopened.inventory.gear == [gear])
        gear.trashed = true; precondition(reopened.save(gear))
        gear.trashed = false; precondition(reopened.save(gear))
        let restored = GearStore(root: root)
        precondition(restored.inventory.gear == [gear])
        let previous = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: root.appendingPathComponent("inventory.previous.json")))
        precondition(previous.gear[0].trashed)
        let roundtrip = try NativeCSV.merge(NativeCSV.export(restored.inventory), into: Inventory()).items
        precondition(roundtrip[0].name == gear.name && roundtrip[0].notes == gear.notes && roundtrip[0].weight == gear.weight)
        var room = Gear(); room.name = "储物间"
        var roomDetail = GearExtras(); roomDetail.isLocation = true
        precondition(store.save(room, extras: roomDetail))
        var shelf = Gear(); shelf.name = "装备柜"
        var shelfDetail = GearExtras(); shelfDetail.isLocation = true; shelfDetail.parentID = room.id
        precondition(store.save(shelf, extras: shelfDetail))
        var bag = Gear(); bag.name = "登山包"; bag.tags = "徒步"; bag.photo = "fixture.png"
        var bagDetail = GearExtras(); bagDetail.parentID = shelf.id
        bagDetail.attachments = [GearAttachment(title: "说明书.txt", file: "fixture.txt")]
        let fixture = Data("test attachment".utf8)
        try fixture.write(to: root.appendingPathComponent("Files/fixture.txt"))
        try fixture.write(to: root.appendingPathComponent("Photos/fixture.png"))
        precondition(store.save(bag, extras: bagDetail))
        var tool = Gear(); tool.name = "包内工具"
        var toolDetail = GearExtras(); toolDetail.parentID = bag.id
        precondition(store.save(tool, extras: toolDetail))
        precondition(store.inventory.location(for: tool.id) == "储物间 / 装备柜")
        var cycle = store.inventory.extras(room.id); cycle.parentID = shelf.id
        precondition(!store.save(room, extras: cycle))
        let oldTag = store.inventory.labels.first { $0.name == "徒步" }!
        var renamed = oldTag; renamed.name = "徒步露营"; renamed.color = "蓝色"
        precondition(store.saveTag(renamed))
        precondition(store.inventory.gear.first { $0.id == bag.id }!.tags == "徒步露营")
        let template = GearTemplate(name: "背包模板", gear: bag, extras: store.inventory.extras(bag.id))
        precondition(store.saveTemplate(template))
        let cloned = store.duplicate(gear, copyAttachments: true, prefix: "副本")
        precondition(cloned.id != gear.id && cloned.name == "副本" + gear.name)
        let exported = NativeCSV.export(store.inventory)
        let merged = try NativeCSV.merge(exported, into: store.inventory)
        precondition(merged.gear.count == store.inventory.gear.count)
        precondition(merged.extras(bag.id).attachments.count == 1 && merged.location(for: tool.id) == "储物间 / 装备柜")
        let empty = GearStore(root: root.appendingPathComponent("empty")).inventory
        let reimported = try NativeCSV.merge(exported, into: empty)
        precondition(reimported.gear.count == store.inventory.gear.count)
        precondition(reimported.location(for: tool.id) == "储物间 / 装备柜")
        let tsv = try NativeCSV.merge("HB.name\tHB.quantity\tHB.location\n水壶\t2\t房间/抽屉", into: empty)
        precondition(tsv.items.count == 1 && tsv.places.count == 2)
        let backupURL = root.appendingPathComponent("test.gearbackup")
        try store.backup(to: backupURL)
        let destination = GearStore(root: root.appendingPathComponent("restored"))
        let restoredBackup = try destination.restore(from: backupURL)
        precondition(restoredBackup && destination.inventory.gear.count == store.inventory.gear.count)
        let restoredBag = destination.inventory.gear.first { $0.id == bag.id }!
        let restoredAttachment = destination.inventory.extras(bag.id).attachments[0]
        let attachmentData = try Data(contentsOf: destination.attachmentURL(restoredAttachment))
        precondition(attachmentData == fixture)
        let restoredTemplate = destination.inventory.templates.first { $0.id == template.id }!
        let templatePhoto = try Data(contentsOf: destination.photoURL(restoredTemplate.gear.photo!))
        precondition(templatePhoto == fixture && restoredBag.photo != bag.photo)
        precondition(destination.inventory.labels.count == store.inventory.labels.count)
        precondition(store.changeRecords([room.id], trash: true))
        precondition(store.inventory.gear.first { $0.id == tool.id }!.trashed)
        precondition(store.changeRecords([room.id], trash: false))
        precondition(!store.inventory.gear.first { $0.id == tool.id }!.trashed)
        let broken = root.appendingPathComponent("inventory.json")
        try Data("invalid JSON".utf8).write(to: broken)
        let damagedStore = GearStore(root: root)
        precondition(!damagedStore.ready && !damagedStore.save(Gear()))
        let unchanged = try String(contentsOf: broken, encoding: .utf8)
        precondition(unchanged == "invalid JSON")
        try FileManager.default.removeItem(at: root)
        print("PASS: CSV/TSV, full-field round-trip, hierarchy cycle rejection, tag rename, templates, photos/files backup restore, duplicate IDs, subtree trash/restore, disk persistence and corrupt-file preservation")
    }
}

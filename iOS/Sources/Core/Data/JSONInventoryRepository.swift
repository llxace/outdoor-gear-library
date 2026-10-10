import Foundation

struct JSONInventoryRepository: InventoryRepository {
    let root: URL
    private var file: URL { root.appendingPathComponent("inventory.json") }

    func load(seedInitialInventory: Bool) throws -> Inventory {
        try prepareDirectories()
        var inventory = try readOrCreate(seedInitialInventory: seedInitialInventory)
        guard (1...9).contains(inventory.version) else { throw CocoaError(.fileReadUnknown) }
        if inventory.version < 9 {
            try backupBeforeMigration()
            inventory = InventoryMigration.upgraded(inventory)
            try inventory.validateRelationships()
            try save(inventory)
        }
        try inventory.validateRelationships()
        return inventory
    }

    func save(_ inventory: Inventory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(inventory)
        if FileManager.default.fileExists(atPath: file.path) {
            try Data(contentsOf: file).write(
                to: root.appendingPathComponent("inventory.previous.json"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }

    private func prepareDirectories() throws {
        for name in ["Photos", "Files"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    private func readOrCreate(seedInitialInventory: Bool) throws -> Inventory {
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: file))
        }
        var inventory = Inventory()
        if seedInitialInventory, let seed = Bundle.main.url(forResource: "InitialInventory", withExtension: "json") {
            inventory = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: seed))
        }
        try save(inventory)
        return inventory
    }

    private func backupBeforeMigration() throws {
        let destination = root.appendingPathComponent("升级前备份", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".gearbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["inventory.json", "Photos", "Files"] {
            try FileManager.default.copyItem(
                at: root.appendingPathComponent(name), to: destination.appendingPathComponent(name))
        }
    }
}

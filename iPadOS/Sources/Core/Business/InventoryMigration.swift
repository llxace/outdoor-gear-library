import Foundation

enum InventoryMigration {
    static func upgraded(_ original: Inventory) -> Inventory {
        var inventory = original
        if inventory.version == 1 { inventory.migrateNativeV1() }
        inventory.version = 9
        inventory.organizeOutdoorCategories()
        return inventory
    }

    static func preparedForSave(_ original: Inventory) throws -> Inventory {
        var inventory = original
        inventory.version = 9
        inventory.organizeOutdoorCategories()
        inventory.constrainPackingQuantities()
        try inventory.validateRelationships()
        return inventory
    }
}

struct BusinessError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

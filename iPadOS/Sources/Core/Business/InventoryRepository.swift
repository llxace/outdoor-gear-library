import Foundation

protocol InventoryRepository {
    var root: URL { get }
    func load(seedInitialInventory: Bool) throws -> Inventory
    func save(_ inventory: Inventory) throws
}

import Foundation
import Combine

/// Presentation state and transaction boundary. Storage and business rules live outside this facade.
final class GearStore: ObservableObject {
    @Published private(set) var inventory = Inventory()
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var ready = false
    @Published var exchangeRates: [String: ExchangeRate] = [:]
    @Published var exchangeLoading = false
    @Published var exchangeError = ""
    private let repository: any InventoryRepository
    var root: URL { repository.root }

    convenience init(root directory: URL? = nil, seedInitialInventory: Bool = true) {
        let root = directory ?? LocalAssetFiles.libraryRoot
        self.init(repository: JSONInventoryRepository(root: root), seedInitialInventory: seedInitialInventory)
    }

    init(repository: any InventoryRepository, seedInitialInventory: Bool = true) {
        self.repository = repository
        do {
            inventory = try repository.load(seedInitialInventory: seedInitialInventory)
            exchangeRates = ExchangeRateRepository(root: root).cachedRates()
            ready = true
            Task { @MainActor in await self.refreshExchangeRates() }
        } catch {
            self.error = "无法读取装备库，原文件已保留：\(error.localizedDescription)"
        }
    }

    @discardableResult func commit(_ next: Inventory) -> Bool {
        guard ready else {
            error = "装备库未成功读取，已暂停写入。"
            return false
        }
        do {
            let prepared = try InventoryMigration.preparedForSave(next)
            try repository.save(prepared)
            inventory = prepared
            return true
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult func updateInventory(_ transform: (Inventory) throws -> Inventory) -> Bool {
        do { return commit(try transform(inventory)) } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult func save(_ gear: Gear) -> Bool {
        save(gear, extras: inventory.extras(gear.id))
    }

    func photoURL(_ name: String) -> URL {
        root.appendingPathComponent("Photos").appendingPathComponent(name)
    }

    @discardableResult func toggleFavorite(_ id: UUID) -> Bool {
        guard inventory.gear.contains(where: { $0.id == id }) else { return false }
        var next = inventory
        if next.favoriteGearIDs.contains(id) {
            next.favoriteGearIDs.removeAll { $0 == id }
        } else {
            next.favoriteGearIDs.append(id)
        }
        return commit(next)
    }
}

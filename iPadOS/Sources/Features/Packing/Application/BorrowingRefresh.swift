import Foundation

extension UserLibraries {
    func refreshBorrowedPackingItems() {
        guard !store.inventory.borrowedPackingItems.isEmpty else { return }
        var next = store.inventory
        var sources: [UUID: GearStore] = [:]
        for owner in Set(next.borrowedPackingItems.map(\.ownerID)) { sources[owner] = library(for: owner) }
        for index in next.borrowedPackingItems.indices {
            let item = next.borrowedPackingItems[index]
            guard let source = sources[item.ownerID], let gear = source.items.first(where: { $0.id == item.gear.id })
            else {
                next.borrowedPackingItems[index].unavailable = true
                continue
            }
            var updated = gear
            updated.photo = item.gear.photo
            next.borrowedPackingItems[index].gear = updated
            next.borrowedPackingItems[index].quantity = min(item.quantity, gear.quantity)
            next.borrowedPackingItems[index].subcategory = source.inventory.subcategory(for: gear)
            next.borrowedPackingItems[index].unavailable = gear.status == "损坏"
            next.borrowedPackingItems[index].ownerName =
                users.first(where: { $0.id == item.ownerID })?.name ?? item.ownerName
        }
        if next.borrowedPackingItems != store.inventory.borrowedPackingItems { _ = store.commit(next) }
    }
}

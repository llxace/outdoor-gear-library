import Foundation

extension Inventory {
    var packingGear: [Gear] {
        items.filter { gear in
            !gear.trashed && gear.status != "损坏" && packingItems.contains(where: { $0.sourceGearID == gear.id })
        }
    }
    func packingQuantity(_ id: UUID) -> Double? {
        guard let item = packingItems.first(where: { $0.sourceGearID == id }),
            let gear = items.first(where: { $0.id == id }), gear.status != "损坏"
        else { return nil }
        return min(item.quantity, gear.quantity)
    }
    mutating func constrainPackingQuantities() {
        let damagedIDs = Set(items.filter { $0.status == "损坏" }.map(\.id))
        packingItems.removeAll { damagedIDs.contains($0.sourceGearID) }
        for i in packingItems.indices {
            if let gear = items.first(where: { $0.id == packingItems[i].sourceGearID }) {
                packingItems[i].quantity = min(packingItems[i].quantity, gear.quantity)
            }
        }
    }
    var packingWeight: Double {
        packingGear.reduce(0) { $0 + $1.weight * (packingQuantity($1.id) ?? 0) }
            + borrowedPackingItems.filter { !$0.unavailable }.reduce(0) {
                $0 + $1.gear.weight * min($1.quantity, $1.gear.quantity)
            }
    }
    var packingValue: Double {
        let own = packingGear.reduce(0.0) { total, gear in
            total + (gear.quantity > 0 ? gear.purchasePrice / gear.quantity * (packingQuantity(gear.id) ?? 0) : 0)
        }
        return borrowedPackingItems.filter { !$0.unavailable }.reduce(own) { total, item in
            total
                + (item.gear.quantity > 0
                    ? item.gear.purchasePrice / item.gear.quantity * min(item.quantity, item.gear.quantity) : 0)
        }
    }
    var missingPackingPrices: Int {
        packingGear.filter { $0.purchasePrice == 0 }.count
            + borrowedPackingItems.filter { !$0.unavailable && $0.gear.purchasePrice == 0 }.count
    }
    var missingPackingWeights: Int {
        packingGear.filter { $0.weight == 0 }.count
            + borrowedPackingItems.filter { !$0.unavailable && $0.gear.weight == 0 }.count
    }
    var unavailablePackingItems: Int {
        packingItems.count - packingGear.count + borrowedPackingItems.filter(\.unavailable).count
    }
    var packingCount: Int { packingGear.count + borrowedPackingItems.filter { !$0.unavailable }.count }
}

import Foundation

extension GearLibrary {
    func setPackingQuantity(_ quantity: Double?, for id: UUID) {
        guard let gear = activeGear.first(where: { $0.id == id }) else { return }
        do {
            inventory["packingItems"] = try PackingOperations.setQuantity(
                quantity, for: gear, in: inventory["packingItems"] as? [[String: Any]] ?? [])
            save()
        } catch {
            alert = error.localizedDescription
        }
    }

    func togglePacked(_ gear: Gear) {
        setPackingQuantity(packingQuantity(for: gear.id) == nil ? min(1, gear.quantity) : nil, for: gear.id)
    }

    func clearPacking() {
        inventory["packingItems"] = []
        inventory["borrowedPackingItems"] = []
        save()
    }

    func addBorrowedGear(_ gear: Gear, ownerID: UUID, ownerName: String, quantity: Double) {
        do {
            guard quantity.isFinite, quantity > 0, quantity <= gear.quantity, gear.status != "损坏" else {
                throw PackingError.invalidQuantity
            }
            var rows = inventory["borrowedPackingItems"] as? [[String: Any]] ?? []
            let existing = borrowedPackingItems.first { $0.ownerName == ownerName && $0.gear.id == gear.id }
            let stableOwnerID = existing?.ownerID ?? ownerID
            let data = try JSONEncoder().encode(gear)
            guard let gearRow = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let row: [String: Any] = [
                "id": existing?.id.uuidString ?? UUID().uuidString,
                "ownerID": stableOwnerID.uuidString,
                "ownerName": ownerName,
                "gear": gearRow,
                "quantity": quantity,
                "unavailable": false
            ]
            if let index = rows.firstIndex(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == existing?.id }) {
                rows[index].merge(row) { _, new in new }
            } else {
                rows.append(row)
            }
            inventory["borrowedPackingItems"] = rows
            save()
        } catch {
            alert = error.localizedDescription
        }
    }

    func updateBorrowedQuantity(_ quantity: Double, for id: UUID) {
        do {
            inventory["borrowedPackingItems"] = try PackingOperations.updateBorrowedQuantity(
                quantity, for: id, in: inventory["borrowedPackingItems"] as? [[String: Any]] ?? [])
            save()
        } catch {
            alert = error.localizedDescription
        }
    }

    func removeBorrowedGear(_ id: UUID) {
        var rows = inventory["borrowedPackingItems"] as? [[String: Any]] ?? []
        rows.removeAll { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == id }
        inventory["borrowedPackingItems"] = rows
        save()
    }
}

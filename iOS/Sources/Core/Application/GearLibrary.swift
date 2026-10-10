import SwiftUI
import Foundation

@MainActor
final class GearLibrary: ObservableObject {
    @Published private(set) var revision = 0
    @Published var alert: String?
    var inventory: [String: Any] = [:]
    private let repository: any InventoryRepository
    private let photosURL: URL

    var gears: [Gear] { decode(inventory["gear"] as? [[String: Any]] ?? []) }
    var activeGear: [Gear] {
        let locations = inventory["details"] as? [String: [String: Any]] ?? [:]
        return gears.filter { !$0.trashed && locations[$0.id.uuidString]?["isLocation"] as? Bool != true }
    }
    var packingItems: [PackingEntry] { decode(inventory["packingItems"] as? [[String: Any]] ?? []) }
    var borrowedPackingItems: [BorrowedPackingEntry] { decode(inventory["borrowedPackingItems"] as? [[String: Any]] ?? []) }
    var packedIDs: Set<UUID> { Set(packingItems.map(\.sourceGearID)) }
    var selectedRoute: [String: Any]? { inventory["selectedRoute"] as? [String: Any] }
    var hikeHistory: [[String: Any]] {
        (inventory["hikeHistory"] as? [[String: Any]] ?? []).filter { $0["deleted"] as? Bool != true }
    }
    var departureDate: Date {
        let plan = inventory["mealPlan"] as? [String: Any] ?? [:]
        let seconds = (plan["startDate"] as? NSNumber)?.doubleValue ?? Date.now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
    var packedGear: [Gear] {
        let ids = packedIDs
        return activeGear.filter { ids.contains($0.id) && $0.status != "损坏" }
    }
    var packedWeight: Double {
        packedGear.reduce(0) { $0 + $1.weight * (packingQuantity(for: $1.id) ?? 0) }
            + borrowedPackingItems.filter { !$0.unavailable }.reduce(0) {
                $0 + $1.gear.weight * min($1.quantity, $1.gear.quantity)
            }
    }
    var packedValue: Double {
        packedGear.reduce(0) { total, gear in
            total + gear.purchasePrice / max(gear.quantity, 1) * (packingQuantity(for: gear.id) ?? 0)
        } + borrowedPackingItems.filter { !$0.unavailable }.reduce(0) { total, item in
            total + item.gear.purchasePrice / max(item.gear.quantity, 1) * min(item.quantity, item.gear.quantity)
        }
    }
    var unavailablePackingCount: Int {
        packingItems.filter { item in
            guard let gear = activeGear.first(where: { $0.id == item.sourceGearID }) else { return true }
            return gear.status == "损坏"
        }.count + borrowedPackingItems.filter(\.unavailable).count
    }
    var missingPackingWeightCount: Int {
        packedGear.filter { $0.weight == 0 }.count
            + borrowedPackingItems.filter { !$0.unavailable && $0.gear.weight == 0 }.count
    }

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inventoryURL = base.appendingPathComponent("inventory.json")
        repository = JSONInventoryRepository(fileURL: inventoryURL)
        photosURL = base.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)

        if let loaded = try? repository.load() {
            inventory = loaded
        } else {
            inventory = ["version": 9, "gear": [], "packingItems": [], "borrowedPackingItems": [], "hikeHistory": [], "categories": Gear.categories]
            save()
        }
    }

    func save() {
        do {
            try repository.save(inventory)
            revision += 1
        } catch {
            alert = "保存失败：\(error.localizedDescription)"
        }
    }

    func gearData() throws -> Data {
        try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
    }

    func photoURL(for name: String) -> URL { photosURL.appendingPathComponent(name) }

    func replaceInventory(_ next: [String: Any]) {
        do {
            try repository.save(next)
            inventory = next
            revision += 1
        } catch {
            alert = "导入失败，现有资料未替换：\(error.localizedDescription)"
        }
    }

    func copyAttachments(from sourceDirectory: URL) {
        for folder in ["Photos", "Files", "Avatars"] {
            let source = sourceDirectory.appendingPathComponent(folder, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let destination = photosURL.deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
                let target = destination.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: file, to: target) }
            }
        }
    }

    func packingQuantity(for id: UUID) -> Double? {
        packingItems.first(where: { $0.sourceGearID == id }).map(\.quantity)
    }

    func updateDepartureDate(_ date: Date) {
        var plan = inventory["mealPlan"] as? [String: Any] ?? [:]
        plan["startDate"] = date.timeIntervalSinceReferenceDate
        inventory["mealPlan"] = plan
        save()
    }

    private func decode<T: Decodable>(_ rows: [[String: Any]]) -> [T] {
        rows.compactMap { row in
            guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }

}

private extension Gear {
    static let categories = ["背包与收纳", "帐篷与睡眠", "服装与配饰", "鞋袜与行走", "炊具与饮水", "照明与电子", "工具与急救", "洗漱与杂项"]
}

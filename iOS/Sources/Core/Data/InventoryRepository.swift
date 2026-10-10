import Foundation

protocol InventoryRepository {
    func load() throws -> [String: Any]
    func save(_ inventory: [String: Any]) throws
}

struct JSONInventoryRepository: InventoryRepository {
    let fileURL: URL

    func load() throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        guard let inventory = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return inventory
    }

    func save(_ inventory: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
}

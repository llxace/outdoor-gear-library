import Foundation

struct InventoryBackupService {
    let inventory: Inventory
    let root: URL
    func backup(to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw BackupError.failure("已有备份不会被覆盖，请选择新名称。") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".gear-backup-" + UUID().uuidString)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(inventory).write(to: staging.appendingPathComponent("inventory.json"), options: .atomic)
            for folder in ["Photos", "Files"] {
                try fm.copyItem(at: root.appendingPathComponent(folder), to: staging.appendingPathComponent(folder))
            }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

}

enum BackupError {
    static func failure(_ message: String) -> NSError {
        NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

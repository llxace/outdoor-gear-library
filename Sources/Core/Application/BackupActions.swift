import Foundation

extension GearStore {
    func backup(to destination: URL) throws {
        try InventoryBackupService(inventory: inventory, root: root).backup(to: destination)
    }

    func restore(from source: URL) throws -> Bool {
        var restorer = BackupAssetRestorer(source: source, root: root)
        let backup = try restorer.read()
        return commit(try BackupMerge.restoring(backup, into: inventory))
    }
}

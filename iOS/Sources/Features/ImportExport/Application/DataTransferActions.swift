import Foundation

extension GearLibrary {
    func importFile(_ url: URL) {
        do {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let sourceDirectory: URL
            let inventoryURL: URL
            var extractedDirectory: URL?
            if url.pathExtension.lowercased() == "zip" {
                let staging = try InventoryArchive.restore(Data(contentsOf: url), to: FileManager.default.temporaryDirectory)
                extractedDirectory = staging
                sourceDirectory = staging
                inventoryURL = staging.appendingPathComponent("inventory.json")
            } else {
                sourceDirectory = url.deletingLastPathComponent()
                inventoryURL = url
            }
            defer { if let extractedDirectory { try? FileManager.default.removeItem(at: extractedDirectory) } }
            guard let incoming = try JSONSerialization.jsonObject(with: Data(contentsOf: inventoryURL)) as? [String: Any],
                  incoming["gear"] is [[String: Any]], incoming["version"] != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            copyAttachments(from: sourceDirectory)
            replaceInventory(incoming)
            if alert == nil { alert = "已导入 \(activeGear.count) 件装备和打包资料。" }
        } catch {
            alert = "无法读取装备库文件：\(error.localizedDescription)"
        }
    }

    func exportURL() -> URL? {
        do {
            let date = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("户外装备库-\(date).json")
            try gearData().write(to: url, options: .atomic)
            return url
        } catch {
            alert = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func backupArchiveURL() -> URL? {
        do {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let data = try InventoryArchive.make(from: base)
            let date = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("户外装备库-完整备份-\(date).zip")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            alert = "完整备份失败：\(error.localizedDescription)"
            return nil
        }
    }
}

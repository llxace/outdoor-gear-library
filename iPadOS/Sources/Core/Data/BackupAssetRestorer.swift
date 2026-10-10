import Foundation

struct BackupAssetRestorer {
    let source: URL
    let root: URL
    private var fileMap: [String: String] = [:]

    init(source: URL, root: URL) {
        self.source = source
        self.root = root
    }

    mutating func read() throws -> Inventory {
        var backup = try JSONDecoder().decode(
            Inventory.self, from: Data(contentsOf: source.appendingPathComponent("inventory.json")))
        guard (1...9).contains(backup.version), Set(backup.gear.map(\.id)).count == backup.gear.count else {
            throw BackupError.failure("备份结构或版本无效。")
        }
        if backup.version == 1 {
            backup.migrateNativeV1()
            backup.version = 2
        }
        try backup.validateRelationships()
        try copyEquipment(&backup)
        try copyTemplates(&backup)
        try copyBorrowedPhotos(&backup)
        try copyHistoryPhotos(&backup)
        return backup
    }
    private mutating func copyFile(_ filename: String, folder: String, sourceFolder: String? = nil) throws -> String {
        guard !filename.isEmpty, filename != ".", filename != "..",
            URL(fileURLWithPath: filename).lastPathComponent == filename
        else { throw BackupError.failure("备份中存在无效附件路径。") }
        let key = folder + "/" + filename
        if let copied = fileMap[key] { return copied }
        let original = source.appendingPathComponent(sourceFolder ?? folder).appendingPathComponent(filename)
        let values = try original.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw BackupError.failure("备份附件不是普通文件。")
        }
        let replacement = UUID().uuidString + "." + original.pathExtension
        try FileManager.default.copyItem(
            at: original, to: root.appendingPathComponent(folder).appendingPathComponent(replacement))
        fileMap[key] = replacement
        return replacement
    }
    private mutating func copyAttachment(_ attachment: GearAttachment) throws -> String {
        let file = source.appendingPathComponent("Files").appendingPathComponent(attachment.file)
        let legacyFolder = attachment.title == "修图原图" && !LocalAssetFiles.exists(file) ? "Photos" : nil
        return try copyFile(attachment.file, folder: "Files", sourceFolder: legacyFolder)
    }
    private mutating func copyAssets(_ gear: inout Gear, _ detail: inout GearExtras) throws {
        if let photo = gear.photo { gear.photo = try copyFile(photo, folder: "Photos") }
        for i in detail.attachments.indices {
            detail.attachments[i].file = try copyAttachment(detail.attachments[i])
        }
    }
    private mutating func copyEquipment(_ backup: inout Inventory) throws {
        for i in backup.gear.indices {
            var detail = backup.extras(backup.gear[i].id)
            try copyAssets(&backup.gear[i], &detail)
            backup.details[backup.gear[i].id.uuidString] = detail
        }
    }

    private mutating func copyTemplates(_ backup: inout Inventory) throws {
        for i in backup.templates.indices {
            var template = backup.templates[i]
            try copyAssets(&template.gear, &template.extras)
            backup.templates[i] = template
        }
    }

    private mutating func copyBorrowedPhotos(_ backup: inout Inventory) throws {
        for i in backup.borrowedPackingItems.indices {
            if let photo = backup.borrowedPackingItems[i].gear.photo {
                backup.borrowedPackingItems[i].gear.photo = try copyFile(photo, folder: "Photos")
            }
        }
    }

    private mutating func copyHistoryPhotos(_ backup: inout Inventory) throws {
        for i in backup.hikeHistory.indices {
            for j in backup.hikeHistory[i].gear.indices {
                if let photo = backup.hikeHistory[i].gear[j].gear.photo {
                    backup.hikeHistory[i].gear[j].gear.photo = try copyFile(photo, folder: "Photos")
                }
            }
        }
    }
}

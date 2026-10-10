import Foundation

extension GearStore {
    var currency: String { inventory.settings.currency }
    var items: [Gear] { inventory.items.filter { !$0.trashed } }

    @discardableResult func save(_ gear: Gear, extras: GearExtras) -> Bool {
        return updateInventory { try GearOperations.save(gear, extras: extras, in: $0) }
    }

    @discardableResult func changeRecords(
        _ ids: Set<UUID>, status: String? = nil, parent: UUID? = nil,
        setParent: Bool = false, tags: String? = nil, trash: Bool? = nil
    ) -> Bool {
        return updateInventory {
            try GearOperations.changeRecords(
                ids, status: status, parent: parent, setParent: setParent, tags: tags, trash: trash, in: $0)
        }
    }

    func duplicate(_ original: Gear, copyAttachments: Bool, prefix: String) -> Gear {
        var gear = original
        gear.id = UUID()
        gear.name = prefix + original.name
        gear.trashed = false
        if !copyAttachments { gear.photo = nil }
        return gear
    }
    func duplicateExtras(_ original: Gear, copyAttachments: Bool) -> GearExtras {
        var detail = inventory.extras(original.id)
        detail.assetID = 0
        detail.importRef = ""
        if !copyAttachments {
            detail.attachments = []
        } else {
            for i in detail.attachments.indices { detail.attachments[i].id = UUID() }
        }
        return detail
    }

    func saveTag(_ tag: GearTag) -> Bool {
        return updateInventory { try GearOperations.saveTag(tag, in: $0) }
    }
    func removeTag(_ tag: GearTag) {
        _ = updateInventory { try GearOperations.removeTag(tag, in: $0) }
    }
    func saveTemplate(_ template: GearTemplate) -> Bool {
        return updateInventory { try GearOperations.saveTemplate(template, in: $0) }
    }
    func removeTemplate(_ template: GearTemplate) {
        _ = updateInventory { try GearOperations.removeTemplate(template, in: $0) }
    }
    func applyTemplate(_ template: GearTemplate, to id: UUID) -> (Gear, GearExtras) {
        var gear = template.gear
        var detail = template.extras
        gear.id = id
        gear.trashed = false
        detail.assetID = 0
        detail.importRef = ""
        return (gear, detail)
    }

    func attachmentURL(_ attachment: GearAttachment) -> URL {
        root.appendingPathComponent("Files").appendingPathComponent(attachment.file)
    }

    func saveSettings(_ settings: LibrarySettings) {
        _ = updateInventory { try GearOperations.saveSettings(settings, in: $0) }
    }
    func ensureIdentifiers() {
        _ = updateInventory { try GearOperations.ensureIdentifiers(in: $0) }
    }
    func normalizeDates() {
        _ = updateInventory { try GearOperations.normalizeDates(in: $0) }
    }

    func setMissingPrimaryPhotos() {
        var next = inventory
        do {
            for i in next.gear.indices where next.gear[i].photo == nil {
                guard let image = next.extras(next.gear[i].id).attachments.first(where: \.isImage) else { continue }
                let name = UUID().uuidString + "." + URL(fileURLWithPath: image.file).pathExtension
                try LocalAssetFiles.copy(from: attachmentURL(image), to: photoURL(name))
                next.gear[i].photo = name
            }
            _ = commit(next)
        } catch { self.error = "设置主照片失败：\(error.localizedDescription)" }
    }

}

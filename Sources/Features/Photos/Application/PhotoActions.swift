import Foundation

extension GearStore {
    @discardableResult func applyProductPhoto(for id: UUID, source: String, result: String) -> Bool {
        guard var gear = inventory.gear.first(where: { $0.id == id }), !gear.trashed,
            LocalAssetFiles.exists(photoURL(source)), LocalAssetFiles.exists(photoURL(result))
        else { return false }
        do {
            let archived = try PhotoOriginalFiles.archive(photoURL(source), root: root)
            var extras = inventory.extras(id)
            extras.attachments.append(GearAttachment(title: "修图原图", file: archived.lastPathComponent, isImage: true))
            gear.photo = result
            if save(gear, extras: extras) { return true }
            LocalAssetFiles.removeDrafts([archived])
        } catch { self.error = "保存修图原图失败：" + error.localizedDescription }
        return false
    }
    @discardableResult func restoreProductPhoto(for id: UUID) -> Bool {
        guard var gear = inventory.gear.first(where: { $0.id == id }), !gear.trashed else { return false }
        var extras = inventory.extras(id)
        guard let original = extras.attachments.last(where: { $0.title == "修图原图" }) else { return false }
        do {
            let restored = try PhotoOriginalFiles.prepareRestore(original.file, root: root)
            gear.photo = restored.name
            extras.attachments.removeAll { $0.id == original.id }
            if save(gear, extras: extras) { return true }
            if let draft = restored.draft { LocalAssetFiles.removeDrafts([draft]) }
        } catch { self.error = "还原照片失败：" + error.localizedDescription }
        return false
    }
}

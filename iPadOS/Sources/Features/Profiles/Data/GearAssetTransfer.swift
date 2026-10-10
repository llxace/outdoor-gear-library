import Foundation

/// Copies a draft's files before saving it in another user's inventory.
struct GearAssetTransfer {
    let source: URL
    let destination: URL
    private var copied: [URL] = []

    init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    mutating func transfer(_ gear: Gear, extras: GearExtras) throws -> (Gear, GearExtras) {
        guard source != destination else { return (gear, extras) }
        do {
            var result = gear
            var detail = extras
            result.location = ""
            detail.parentID = nil
            detail.locationOverrideID = nil
            detail.assetID = 0
            detail.importRef = ""
            if let photo = result.photo { result.photo = try copy(photo, folder: "Photos") }
            for i in detail.attachments.indices {
                detail.attachments[i].file = try copy(detail.attachments[i].file, folder: "Files")
            }
            return (result, detail)
        } catch {
            LocalAssetFiles.removeDrafts(copied)
            throw error
        }
    }

    private mutating func copy(_ name: String, folder: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", URL(fileURLWithPath: name).lastPathComponent == name else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let replacement = UUID().uuidString + "." + URL(fileURLWithPath: name).pathExtension
        let target = destination.appendingPathComponent(folder).appendingPathComponent(replacement)
        try LocalAssetFiles.copy(from: source.appendingPathComponent(folder).appendingPathComponent(name), to: target)
        copied.append(target)
        return replacement
    }
}

import Foundation

/// Originals are real attachments; restored attachments can be promoted back to primary photos.
enum PhotoOriginalFiles {
    static func archive(_ source: URL, root: URL) throws -> URL {
        let target = root.appendingPathComponent("Files").appendingPathComponent(
            UUID().uuidString + "." + source.pathExtension)
        try LocalAssetFiles.copy(from: source, to: target)
        return target
    }
    static func prepareRestore(_ filename: String, root: URL) throws -> (name: String, draft: URL?) {
        let legacyPhoto = root.appendingPathComponent("Photos").appendingPathComponent(filename)
        if LocalAssetFiles.exists(legacyPhoto) { return (filename, nil) }
        let source = root.appendingPathComponent("Files").appendingPathComponent(filename)
        let name = UUID().uuidString + "." + source.pathExtension
        let target = root.appendingPathComponent("Photos").appendingPathComponent(name)
        try LocalAssetFiles.copy(from: source, to: target)
        return (name, target)
    }
}

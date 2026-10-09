import Foundation

/// File operations shared by image import, preview and temporary crop drafts.
enum LocalAssetFiles {
    static var libraryRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutdoorGearNative", isDirectory: true)
    }
    static func imageData(at url: URL) throws -> Data { try Data(contentsOf: url) }
    static func copy(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }
    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    static func write(_ data: Data, to destination: URL) throws { try data.write(to: destination, options: .atomic) }
    static func removeDrafts(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
    static func saveAvatarDraft(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "gear-avatar-" + UUID().uuidString + ".png")
        try write(data, to: url)
        return url
    }
}

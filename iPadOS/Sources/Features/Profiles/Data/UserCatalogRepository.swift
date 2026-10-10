import Foundation
import UIKit

struct UserCatalogRepository {
    let root: URL
    private var file: URL { root.appendingPathComponent("users.json") }
    var exists: Bool { LocalAssetFiles.exists(file) }
    func load() throws -> UserCatalog {
        try JSONDecoder().decode(UserCatalog.self, from: Data(contentsOf: file))
    }
    func save(users: [LibraryUser], selectedID: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(UserCatalog(users: users, selectedID: selectedID)).write(to: file, options: .atomic)
    }
    func copyAvatar(_ source: URL) throws -> URL {
        guard UIImage(contentsOfFile: source.path) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let folder = root.appendingPathComponent("Avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + source.pathExtension
        let destination = folder.appendingPathComponent(name)
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        return destination
    }
}

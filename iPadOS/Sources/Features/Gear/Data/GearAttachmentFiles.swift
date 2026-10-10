import Foundation
import UIKit

enum GearAttachmentFiles {
    static func importFile(_ url: URL, root: URL) throws -> GearAttachment {
        let filename = UUID().uuidString + "." + url.pathExtension
        let target = root.appendingPathComponent("Files").appendingPathComponent(filename)
        try LocalAssetFiles.copy(from: url, to: target)
        return GearAttachment(title: url.lastPathComponent, file: filename, isImage: UIImage(contentsOfFile: url.path) != nil)
    }
    static func exportFile(_ source: URL, to destination: URL) throws {
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }
}

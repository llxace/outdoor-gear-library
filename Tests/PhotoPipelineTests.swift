import Foundation
import AppKit

@main struct PhotoPipelineChecks {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "PhotoChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        assertions += 1
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoPipeline-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GearStore(root: root, seedInitialInventory: false)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<128 {
            for x in 0..<96 {
                let offset = y * bitmap.bytesPerRow + x * 4
                let shade: UInt8 = (20..<76).contains(x) && (20..<108).contains(y) ? 0 : 255
                for component in 0..<3 { bitmap.bitmapData![offset + component] = shade }
                bitmap.bitmapData![offset + 3] = 255
            }
        }
        let fixture = bitmap.representation(using: .png, properties: [:])!
        let source = store.photoURL("source.png"); let output = store.photoURL("result.png")
        try fixture.write(to: source)
        try ProductPhotoProcessor.process(source: source, destination: output, white: false, shadow: false)
        let normalized = NSBitmapImageRep(data: try Data(contentsOf: output))!
        try expect(normalized.pixelsWide == 1024 && normalized.pixelsHigh == 1024, "photo normalized to 1024 square")
        try expect(try Data(contentsOf: source) == fixture, "processing preserves source")
        let whiteOutput = store.photoURL("white-shadow.png")
        let plainOutput = store.photoURL("white-plain.png")
        try ProductPhotoProcessor.process(source: source, destination: whiteOutput, white: true, shadow: true)
        try ProductPhotoProcessor.process(source: source, destination: plainOutput, white: true, shadow: false)
        let white = NSBitmapImageRep(data: try Data(contentsOf: whiteOutput))!
        try expect(white.pixelsWide == 1024 && white.pixelsHigh == 1024, "cutout is 1024 square")
        try expect(try Data(contentsOf: whiteOutput) != Data(contentsOf: plainOutput), "shadow option affects output")
        try expect(try Data(contentsOf: source) == fixture, "cutout preserves source")
        var gear = Gear(); gear.name = "照片测试装备"; gear.photo = "source.png"
        try expect(store.save(gear), "save photo fixture")
        try expect(store.applyProductPhoto(for: gear.id, source: "source.png", result: "result.png"), "apply processed photo")
        let original = store.inventory.extras(gear.id).attachments.last!
        try expect(LocalAssetFiles.exists(store.attachmentURL(original)), "original attachment is readable")
        try expect(try Data(contentsOf: store.attachmentURL(original)) == fixture, "original attachment bytes")
        let backup = root.appendingPathComponent("processed.gearbackup")
        try store.backup(to: backup)
        let destination = GearStore(root: root.appendingPathComponent("restored"), seedInitialInventory: false)
        try expect(try destination.restore(from: backup), "processed photo backup restores")
        try expect(destination.restoreProductPhoto(for: gear.id), "restore original after backup")
        let restored = destination.inventory.gear.first { $0.id == gear.id }!
        try expect(try Data(contentsOf: destination.photoURL(restored.photo!)) == fixture, "restored original bytes")
        try expect(store.restoreProductPhoto(for: gear.id), "restore original locally")
        try expect(store.inventory.extras(gear.id).attachments.isEmpty, "restore consumes original marker")
        // Version 0.19 stored this attachment filename in Photos instead of Files.
        var legacy = store.inventory
        legacy.gear[0].photo = "result.png"
        legacy.details[gear.id.uuidString]!.attachments = [GearAttachment(title: "修图原图", file: "source.png", isImage: true)]
        try JSONEncoder().encode(legacy).write(to: backup.appendingPathComponent("inventory.json"))
        let legacyTarget = GearStore(root: root.appendingPathComponent("legacy"), seedInitialInventory: false)
        try expect(try legacyTarget.restore(from: backup), "legacy edited-photo backup restores")
        try expect(legacyTarget.restoreProductPhoto(for: gear.id), "legacy original recoverable")
        let invalid = store.photoURL("invalid.png"); try Data("not an image".utf8).write(to: invalid)
        var rejected = false
        let invalidOutput = store.photoURL("invalid-result.png")
        do { try ProductPhotoProcessor.process(source: invalid, destination: invalidOutput, white: false, shadow: false) } catch { rejected = true }
        try expect(rejected && !LocalAssetFiles.exists(invalidOutput), "invalid image rejected without output")
        try expect(try Data(contentsOf: invalid) == Data("not an image".utf8), "invalid source preserved")
        print("PASS: \(assertions) assertions; image normalization, source preservation, photo originals, processed and legacy backup restore, invalid-image safety")
    }
}

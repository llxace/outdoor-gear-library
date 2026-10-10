import Foundation

/// A small ZIP store writer/reader keeps the backup format dependency free.
/// It supports stored entries, matching the Mac app's directory backup contents.
enum InventoryArchive {
    private struct Entry {
        let name: String
        let size: UInt32
        let crc: UInt32
        let offset: UInt32
    }

    static func make(from root: URL) throws -> Data {
        let manager = FileManager.default
        var files: [(String, URL)] = [("inventory.json", root.appendingPathComponent("inventory.json"))]
        for folder in ["Photos", "Files", "Avatars"] {
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            guard manager.fileExists(atPath: directory.path) else { continue }
            guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { continue }
                if values.isRegularFile == true {
                    files.append(("\(folder)/" + url.path.replacingOccurrences(of: directory.path + "/", with: ""), url))
                }
            }
        }
        guard files.count <= 65_535 else { throw failure("备份文件数量超出 ZIP 格式限制。") }
        var output = Data()
        var entries: [Entry] = []
        for (name, url) in files {
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            guard bytes.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw failure("备份超过 4 GB，无法打包。")
            }
            let nameData = Data(name.utf8)
            guard nameData.count <= Int(UInt16.max) else { throw failure("备份文件名过长。") }
            let crc = crc32(bytes)
            let offset = UInt32(output.count)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(crc); output.appendLE(UInt32(bytes.count)); output.appendLE(UInt32(bytes.count))
            output.appendLE(UInt16(nameData.count)); output.appendLE(UInt16(0)); output.append(nameData); output.append(bytes)
            entries.append(Entry(name: name, size: UInt32(bytes.count), crc: crc, offset: offset))
        }
        let centralOffset = UInt32(output.count)
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            output.appendLE(UInt32(0x02014b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(20))
            output.appendLE(UInt16(0x0800)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(entry.crc); output.appendLE(entry.size); output.appendLE(entry.size)
            output.appendLE(UInt16(nameData.count)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt32(0)); output.appendLE(entry.offset)
            output.append(nameData)
        }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(centralSize); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        return output
    }

    static func restore(_ data: Data, to directory: URL) throws -> URL {
        guard data.count <= 1_000_000_000, let end = data.lastRange(of: Data([0x50, 0x4b, 0x05, 0x06]))?.lowerBound,
              let total = data.readLE(UInt16.self, at: end + 10),
              let centralOffset = data.readLE(UInt32.self, at: end + 16) else {
            throw failure("不是有效的装备库 ZIP 备份。")
        }
        let staging = directory.appendingPathComponent("gear-restore-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var cursor = Int(centralOffset)
            var totalBytes = 0
            var inventoryFound = false
            for _ in 0..<total {
                guard data.readLE(UInt32.self, at: cursor) == 0x02014b50,
                      let method = data.readLE(UInt16.self, at: cursor + 10), method == 0,
                      let compressedSize = data.readLE(UInt32.self, at: cursor + 20),
                      let size = data.readLE(UInt32.self, at: cursor + 24),
                      compressedSize == size, size <= 100_000_000,
                      let expectedCRC = data.readLE(UInt32.self, at: cursor + 16),
                      let nameLength = data.readLE(UInt16.self, at: cursor + 28),
                      let extraLength = data.readLE(UInt16.self, at: cursor + 30),
                      let commentLength = data.readLE(UInt16.self, at: cursor + 32),
                      let localOffset = data.readLE(UInt32.self, at: cursor + 42) else {
                    throw failure("备份 ZIP 结构不受支持或已损坏。")
                }
                let nameStart = cursor + 46
                let nameEnd = nameStart + Int(nameLength)
                guard nameEnd <= data.count, let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                    throw failure("备份中包含无效文件名。")
                }
                cursor = nameEnd + Int(extraLength) + Int(commentLength)
                totalBytes += Int(size)
                guard totalBytes <= 1_000_000_000 else { throw failure("备份解压后超过 1 GB，已停止导入。") }
                let components = name.split(separator: "/")
                guard !name.hasPrefix("/"), !components.contains(".."), !components.contains(".") else {
                    throw failure("备份中包含不安全的文件路径。")
                }
                guard data.readLE(UInt32.self, at: Int(localOffset)) == 0x04034b50,
                      let localNameLength = data.readLE(UInt16.self, at: Int(localOffset) + 26),
                      let localExtraLength = data.readLE(UInt16.self, at: Int(localOffset) + 28) else {
                    throw failure("备份中的文件头损坏。")
                }
                let payloadStart = Int(localOffset) + 30 + Int(localNameLength) + Int(localExtraLength)
                let payloadEnd = payloadStart + Int(size)
                guard payloadEnd <= data.count else { throw failure("备份文件内容不完整。") }
                let target = staging.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let payload = Data(data[payloadStart..<payloadEnd])
                guard crc32(payload) == expectedCRC else { throw failure("备份中的文件校验失败：\(name)") }
                try payload.write(to: target, options: .atomic)
                if name == "inventory.json" { inventoryFound = true }
            }
            let inventoryURL = staging.appendingPathComponent("inventory.json")
            guard inventoryFound, let inventoryData = try? Data(contentsOf: inventoryURL),
                  let inventory = try? JSONSerialization.jsonObject(with: inventoryData) as? [String: Any],
                  inventory["version"] != nil, inventory["gear"] is [[String: Any]] else {
                throw failure("备份中找不到有效的 inventory.json。")
            }
            return staging
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ 0xffffffff
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "InventoryArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return nil }
        return self[offset..<(offset + MemoryLayout<T>.size)].withUnsafeBytes { buffer in
            guard let value = buffer.baseAddress?.assumingMemoryBound(to: T.self).pointee else { return nil }
            return T(littleEndian: value)
        }
    }
}

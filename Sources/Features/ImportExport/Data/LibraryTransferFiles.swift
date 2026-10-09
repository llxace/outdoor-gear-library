import Foundation

struct LibraryTransferFiles {
    static func exportCSV(_ inventory: Inventory, to url: URL) throws {
        try ("\u{FEFF}" + NativeCSV.export(inventory)).write(to: url, atomically: true, encoding: .utf8)
    }
    static func importCSV(from url: URL, into inventory: Inventory) throws -> Inventory {
        try NativeCSV.merge(String(contentsOf: url, encoding: .utf8), into: inventory)
    }
    static func backupDestination(in root: URL) throws -> URL {
        let directory = root.appendingPathComponent("导入前备份", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString + ".gearbackup")
    }
    static func historicalTrack(at url: URL) throws -> HistoricalTrackImport {
        try HistoricalTrackImport.read(Data(contentsOf: url), filename: url.lastPathComponent)
    }
}

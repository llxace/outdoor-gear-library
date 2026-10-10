import Foundation

struct CSVImportRow {
    let header: [String]
    let row: [String]
    let line: Int

    func value(_ names: String...) -> String {
        for name in names { if let index = header.firstIndex(of: name), index < row.count { return row[index] } }
        return ""
    }
    func number(_ value: String, fallback: Double = 0) throws -> Double {
        if value.isEmpty { return fallback }
        guard let value = Double(value), value.isFinite, value >= 0 else { throw failure("第 \(line + 2) 行数字无效。") }
        return value
    }
    func flag(_ value: String) throws -> Bool {
        if value.isEmpty { return false }
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw failure("第 \(line + 2) 行布尔值无效。")
        }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "NativeCSV", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

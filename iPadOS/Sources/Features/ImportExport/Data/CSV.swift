import Foundation

enum CSV {
    static func parse(_ text: String, delimiter: Unicode.Scalar = ",") throws -> [[String]] {
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: "").unicodeScalars)
        var reader = Reader(chars: chars, delimiter: delimiter)
        return try reader.read()
    }
    private struct Reader {
        let chars: [Unicode.Scalar]
        let delimiter: Unicode.Scalar
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var index = 0
        mutating func finishRow() {
            row.append(cell)
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
            cell = ""
        }
        mutating func read() throws -> [[String]] {
            while index < chars.count {
                let char = chars[index]
                if char == "\"" {
                    if quoted && index + 1 < chars.count && chars[index + 1] == "\"" {
                        cell.append("\"")
                        index += 1
                    } else {
                        quoted.toggle()
                    }
                } else if char == delimiter && !quoted {
                    row.append(cell)
                    cell = ""
                } else if (char == "\n" || char == "\r") && !quoted {
                    finishRow()
                    if char == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
                } else {
                    cell.unicodeScalars.append(char)
                }
                index += 1
            }
            if quoted { throw CocoaError(.fileReadCorruptFile) }
            finishRow()
            return rows
        }
    }
    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\r\n")
    }
}

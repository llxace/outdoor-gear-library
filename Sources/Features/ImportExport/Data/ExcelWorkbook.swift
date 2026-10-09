import Foundation

struct ExcelWorkbook {
    let url: URL
    let sheets: [ExcelSheet]
    private let shared: [String]
    private let dateStyles: Set<Int>
    private let date1904: Bool
    static func failure(_ message: String) -> NSError {
        NSError(domain: "ExcelImport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func part(_ path: String, from url: URL, optional: Bool = false) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 32_000_000 {
                process.terminate()
                throw failure("工作表过大，请拆分后导入（单个 XML 上限 32 MB）。")
            }
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 && !(optional && data.isEmpty) {
            throw failure("无法读取 Excel。请使用未加密的 .xlsx 文件；旧 .xls 请先在 Excel 或 WPS 中另存为 .xlsx。")
        }
        return data
    }
    init(url: URL) throws {
        self.url = url
        let workbook = try ExcelXML.parse(Self.part("xl/workbook.xml", from: url))
        let relationships = try ExcelXML.parse(Self.part("xl/_rels/workbook.xml.rels", from: url))
        var paths: [String: String] = [:]
        for relation in relationships.children where relation.name == "Relationship" {
            guard let id = relation.attributes["Id"], let target = relation.attributes["Target"],
                relation.attributes["TargetMode"] != "External"
            else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            if path.hasPrefix("xl/worksheets/"), !path.contains("..") { paths[id] = path }
        }
        sheets = (workbook.child("sheets")?.children ?? []).compactMap { node in
            guard let name = node.attributes["name"], let id = node.attributes["r:id"], let path = paths[id] else {
                return nil
            }
            return ExcelSheet(name: name, path: path)
        }
        guard !sheets.isEmpty else { throw Self.failure("没有可导入的工作表。") }
        date1904 = ["1", "true"].contains(workbook.child("workbookPr")?.attributes["date1904"] ?? "")
        let strings = try Self.part("xl/sharedStrings.xml", from: url, optional: true)
        shared =
            strings.isEmpty
            ? []
            : try ExcelXML.parse(strings).children.filter { $0.name == "si" }.map {
                $0.children.filter { $0.name == "t" || $0.name == "r" }.map(\.content).joined()
            }
        dateStyles = try Self.readDateStyles(from: url)
    }
    private static func readDateStyles(from url: URL) throws -> Set<Int> {
        let styles = try Self.part("xl/styles.xml", from: url, optional: true)
        var dates = Set<Int>()
        if !styles.isEmpty {
            let tree = try ExcelXML.parse(styles)
            var dateFormats = Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47])
            for format in tree.child("numFmts")?.children ?? [] {
                guard let id = Int(format.attributes["numFmtId"] ?? ""), let code = format.attributes["formatCode"]
                else { continue }
                let stripped = code.replacingOccurrences(
                    of: "\"[^\"]*\"|\\[[^\\]]*\\]|\\\\.", with: "", options: .regularExpression
                ).lowercased()
                if stripped.contains("yy") || stripped.contains("dd") || stripped.contains("h:") {
                    dateFormats.insert(id)
                }
            }
            for (index, style) in (tree.child("cellXfs")?.children ?? []).enumerated() {
                if dateFormats.contains(Int(style.attributes["numFmtId"] ?? "") ?? 0) { dates.insert(index) }
            }
        }
        return dates
    }
    func rows(in sheet: ExcelSheet) throws -> [[String]] {
        let tree = try ExcelXML.parse(Self.part(sheet.path, from: url))
        var rows: [[String]] = []
        for node in tree.child("sheetData")?.children ?? [] where node.name == "row" {
            let rowNumber = Int(node.attributes["r"] ?? "") ?? rows.count + 1
            guard rowNumber > 0, rowNumber <= 50_000 else { throw Self.failure("工作表超过 50,000 行，请拆分后导入。") }
            while rows.count < rowNumber { rows.append([]) }
            var row: [String] = []
            for cell in node.children where cell.name == "c" {
                let address = cell.attributes["r"] ?? ""
                var column = 0
                for scalar in address.uppercased().unicodeScalars where (65...90).contains(scalar.value) {
                    column = column * 26 + Int(scalar.value - 64)
                }
                if column == 0 { column = row.count + 1 }
                guard column <= 512 else { throw Self.failure("工作表超过 512 列，请删除多余列后导入。") }
                while row.count < column { row.append("") }
                let value = try cellValue(cell, address: address)
                row[column - 1] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            rows[rowNumber - 1] = row
        }
        return rows
    }
    private func cellValue(_ cell: ExcelNode, address: String) throws -> String {
        var value = cell.child("v")?.content ?? ""
        switch cell.attributes["t"] {
        case "s":
            guard let index = Int(value), shared.indices.contains(index) else {
                throw Self.failure("\(address) 的文本索引无效。")
            }
            value = shared[index]
        case "inlineStr": value = cell.child("is")?.content ?? ""
        case "b": value = value == "1" ? "是" : "否"
        case "e": throw Self.failure("\(address) 有公式错误 \(value)，请在 Excel/WPS 修正后保存。")
        default:
            if cell.child("f") != nil && cell.child("v") == nil {
                throw Self.failure("\(address) 的公式没有保存计算结果，请在 Excel/WPS 重新计算并保存。")
            }
            if let style = Int(cell.attributes["s"] ?? ""), dateStyles.contains(style), let days = Double(value) {
                let base = date1904 ? "1904-01-01" : "1899-12-30"
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: base) {
                    value = formatter.string(from: date.addingTimeInterval(days * 86400))
                }
            }
        }
        return value
    }
}

import Foundation
import zlib

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
        let archive = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let entry = zipEntry(path, in: archive) else {
            if optional { return Data() }
            throw failure("Excel 工作簿缺少 \(path)，请确认文件未损坏。")
        }
        let (offset, compressedSize, uncompressedSize, method) = entry
        guard uncompressedSize <= 32_000_000, offset >= 0, compressedSize >= 0,
              offset + compressedSize <= archive.count else {
            throw failure("工作表过大或压缩数据无效（单个 XML 上限 32 MB）。")
        }
        let compressed = archive.subdata(in: offset..<(offset + compressedSize))
        if method == 0 { return compressed }
        guard method == 8 else { throw failure("Excel 使用了不支持的压缩方法。") }
        return try decompressArchiveEntry(compressed, size: uncompressedSize)
    }

    private static func decompressArchiveEntry(_ compressed: Data, size: Int) throws -> Data {
        var output = Data(count: size)
        var stream = z_stream()
        let status = compressed.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination -> Int32 in
                guard let inBase = input.bindMemory(to: Bytef.self).baseAddress,
                      let outBase = destination.bindMemory(to: Bytef.self).baseAddress else { return Z_STREAM_ERROR }
                stream.next_in = UnsafeMutablePointer(mutating: inBase)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outBase
                stream.avail_out = uInt(size)
                let initialized = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard initialized == Z_OK else { return initialized }
                let result = inflate(&stream, Z_FINISH)
                inflateEnd(&stream)
                return result
            }
        }
        guard status == Z_STREAM_END else { throw failure("Excel 表格解压失败，请使用未加密的 .xlsx 文件。") }
        return output
    }
    private static func zipEntry(_ path: String, in data: Data) -> (Int, Int, Int, UInt16)? {
        func u16(_ i: Int) -> UInt16 { data[i..<(i + 2)].enumerated().reduce(UInt16(0)) { $0 | UInt16($1.element) << UInt16($1.offset * 8) } }
        func u32(_ i: Int) -> UInt32 { data[i..<(i + 4)].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) } }
        guard data.count >= 22 else { return nil }
        let lower = max(0, data.count - 65_557)
        var eocd: Int?
        for i in stride(from: data.count - 22, through: lower, by: -1) where u32(i) == 0x06054b50 { eocd = i; break }
        guard let eocd, let count = Int(exactly: u16(eocd + 10)), let directory = Int(exactly: u32(eocd + 16)) else { return nil }
        var cursor = directory
        for _ in 0..<count {
            guard cursor + 46 <= data.count, u32(cursor) == 0x02014b50 else { return nil }
            let method = u16(cursor + 10), compressed = Int(u32(cursor + 20)), uncompressed = Int(u32(cursor + 24))
            let nameLength = Int(u16(cursor + 28)), extraLength = Int(u16(cursor + 30)), commentLength = Int(u16(cursor + 32))
            let local = Int(u32(cursor + 42))
            guard cursor + 46 + nameLength + extraLength + commentLength <= data.count else { return nil }
            let name = String(decoding: data[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            if name == path {
                guard local + 30 <= data.count, u32(local) == 0x04034b50 else { return nil }
                let dataStart = local + 30 + Int(u16(local + 26)) + Int(u16(local + 28))
                return (dataStart, compressed, uncompressed, method)
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return nil
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

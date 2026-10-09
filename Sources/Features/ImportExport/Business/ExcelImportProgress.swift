import Foundation

struct ExcelImportProgress {
    var next: Inventory
    var names: [String] = []
    var warnings: [String] = []
    var added = 0
    var updated = 0
    var skipped = 0

    mutating func append(_ row: [String], headers: [String], mapping: [String], line: Int, update: Bool) throws {
        func value(_ field: String) -> String {
            guard let index = mapping.firstIndex(of: field), row.indices.contains(index) else { return "" }
            return row[index]
        }
        let name = value("名称")
        if name.isEmpty {
            if row.contains(where: { !$0.isEmpty }) { skipped += 1 }
            return
        }
        let ref = value("装备ID")
        let previous = update && !ref.isEmpty ? next.gear.first { next.extras($0.id).importRef == ref } : nil
        var values: [String: String] = [:]
        if let previous {
            let exported = try CSV.parse(NativeCSV.export(next, records: [previous]))
            for (column, content) in zip(exported[0], exported[1]) { values[column] = content }
        }
        values["HB.name"] = name
        // 没有标识时新增；不按名称猜测覆盖关系。
        values["HB.import_ref"] = update ? ref : ""
        applyFields(row, headers: headers, mapping: mapping, line: line, values: &values)
        values["HB.import_ref"] = update ? ref : ""
        // 损坏标识优先于“已购”等状态。
        if ["☑", "是", "true", "1", "损坏", "已损坏"].contains(value("装备损坏").lowercased()) { values["Native.status"] = "损坏" }
        let columns = values.keys.sorted()
        next = try NativeCSV.merge(CSV.encode([columns, columns.map { values[$0] ?? "" }]), into: next)
        names.append(name)
        if previous == nil { added += 1 } else { updated += 1 }
    }

    private mutating func applyFields(
        _ row: [String], headers: [String], mapping: [String], line: Int, values: inout [String: String]
    ) {
        for (index, field) in mapping.enumerated() where row.indices.contains(index) && headers.indices.contains(index)
        {
            let raw = row[index]
            if field == "忽略" || raw.isEmpty { continue }
            if ["数量", "单件重量(g)", "购买价格"].contains(field) {
                applyNumber(raw, field: field, header: headers[index], line: line, values: &values)
            } else if field == "装备损坏" {
                if ["☑", "是", "true", "1", "损坏", "已损坏"].contains(raw.lowercased()) { values["Native.status"] = "损坏" }
            } else if field == "状态" {
                if ["已购", "已购买", "正常", "可用"].contains(raw) {
                    values["Native.status"] = "可用"
                } else if ["待购", "想买", "待购买"].contains(raw) {
                    values["Native.status"] = "想买"
                } else if ["借出", "损坏", "已出售"].contains(raw) {
                    values["Native.status"] = raw
                }
            } else if let destination = ExcelImport.destinations[field] {
                values[destination] = raw
            }
        }
    }

    private mutating func applyNumber(
        _ raw: String, field: String, header: String, line: Int, values: inout [String: String]
    ) {
        var numeric = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
        for token in ["￥", "¥", "元", "约", "≈"] { numeric = numeric.replacingOccurrences(of: token, with: "") }
        let kilograms =
            field == "单件重量(g)" && (numeric.lowercased().hasSuffix("kg") || header.lowercased().contains("kg"))
        if field == "单件重量(g)" {
            numeric = numeric.lowercased().replacingOccurrences(of: "kg", with: "").replacingOccurrences(
                of: "g", with: ""
            ).replacingOccurrences(of: "克", with: "")
        }
        if let number = Double(numeric), number.isFinite, number >= 0, field != "数量" || number > 0 {
            values[ExcelImport.destinations[field]!] = String(kilograms ? number * 1000 : number)
        } else {
            warnings.append("第 \(line) 行“\(header)”：\(raw)，未写入数字字段，请检查原表。")
        }
    }

    func finish() throws -> ExcelImportResult {
        guard !names.isEmpty else { throw ExcelWorkbook.failure("没有找到装备记录，请检查工作表、表头行和名称列。") }
        return ExcelImportResult(
            inventory: next, names: names, added: added, updated: updated, skipped: skipped, warnings: warnings)
    }
}

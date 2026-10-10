import Foundation

enum ExcelImport {
    static let fields = [
        "忽略", "名称", "装备ID", "分类", "品牌", "型号", "数量", "单件重量(g)", "购买价格", "购买渠道", "购买日期", "状态", "装备损坏", "备注",
    ]
    static let destinations = [
        "名称": "HB.name", "装备ID": "HB.import_ref", "分类": "Native.category", "品牌": "HB.manufacturer",
        "型号": "HB.model_number", "数量": "HB.quantity", "单件重量(g)": "Native.weight_g", "购买价格": "HB.purchase_price",
        "购买渠道": "HB.purchase_from", "购买日期": "HB.purchase_time", "状态": "Native.status", "备注": "HB.notes",
    ]
    static func guess(_ header: String) -> String {
        let compact = header.lowercased().replacingOccurrences(of: " ", with: "")
        let aliases: [String: [String]] = [
            "名称": ["名称", "装备名称", "物品名称", "商品名称", "hb.name"],
            "装备ID": ["装备id", "装备编号", "hb.import_ref"],
            "分类": ["分类", "子类", "类别", "native.category"],
            "品牌": ["品牌", "制造商", "hb.manufacturer"], "型号": ["型号", "型号/系列", "hb.model_number"],
            "数量": ["数量", "件数", "hb.quantity"],
            "单件重量(g)": ["重量（g）", "重量(g)", "单件重量(g)", "重量", "重量(kg)", "重量（kg）", "native.weight_g"],
            "购买价格": ["购买价格", "购买价格(元)", "购买价格（元）", "价格", "净支出", "hb.purchase_price"],
            "购买渠道": ["购买平台", "购买渠道", "hb.purchase_from"], "购买日期": ["购买日期", "hb.purchase_time"],
            "状态": ["状态", "native.status"], "装备损坏": ["装备损坏", "是否损坏"],
            "备注": ["备注", "使用/维护备注", "hb.notes"],
        ]
        return aliases.first { $0.value.contains(compact) }?.key ?? "忽略"
    }
    static func headerRow(_ rows: [[String]]) -> Int {
        rows.prefix(30).firstIndex { $0.contains { guess($0) == "名称" } } ?? 0
    }
    static func mapping(_ headers: [String]) -> [String] {
        var used = Set<String>()
        return headers.map { header in
            if header.isEmpty { return "忽略" }
            let field = guess(header)
            if field != "忽略", !used.insert(field).inserted { return "忽略" }
            return field
        }
    }
    static func prepare(rows: [[String]], headerRow: Int, mapping: [String], into existing: Inventory, update: Bool)
        throws -> ExcelImportResult
    {
        guard rows.indices.contains(headerRow), mapping.contains("名称") else {
            throw ExcelWorkbook.failure("请选择表头行，并将装备名称列对应到“名称”。")
        }
        let headers = rows[headerRow]
        let assigned = mapping.filter { $0 != "忽略" }
        guard Set(assigned).count == assigned.count else { throw ExcelWorkbook.failure("同一个标准字段只能对应一列；其他列可设为忽略。") }
        var progress = ExcelImportProgress(next: existing)
        for (offset, row) in rows.dropFirst(headerRow + 1).enumerated() {
            try progress.append(row, headers: headers, mapping: mapping, line: headerRow + offset + 2, update: update)
        }
        return try progress.finish()
    }
}

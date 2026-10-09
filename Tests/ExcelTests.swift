import Foundation

@main struct ExcelChecks {
    static func main() throws {
        guard let workbookPath = CommandLine.arguments.dropFirst().first else {
            print("Pass a six-sheet workbook with --excel to run this check.")
            return
        }
        let file = URL(fileURLWithPath: workbookPath)
        let workbook = try ExcelWorkbook(url: file)
        precondition(workbook.sheets.count == 6)
        let rows = try workbook.rows(in: workbook.sheets.first { $0.name == "装备主库" }!)
        let header = ExcelImport.headerRow(rows)
        precondition(header == 4)
        let mapping = ExcelImport.mapping(rows[header])
        let result = try ExcelImport.prepare(rows: rows, headerRow: header, mapping: mapping, into: Inventory(), update: true)
        precondition(result.added == 35 && result.updated == 0)
        let tent = result.inventory.items.first { result.inventory.extras($0.id).importRef == "EQ-001" }!
        precondition(tent.purchasePrice == 619 && tent.weight == 2000 && tent.purchaseFrom == "闲鱼")
        precondition(ExcelImport.guess("官网链接") == "忽略")
        let repeatImport = try ExcelImport.prepare(rows: rows, headerRow: header, mapping: mapping, into: result.inventory, update: true)
        precondition(repeatImport.added == 0 && repeatImport.updated == 35 && repeatImport.inventory.items.count == 35)
        let copies = try ExcelImport.prepare(rows: rows, headerRow: header, mapping: mapping, into: result.inventory, update: false)
        precondition(copies.added == 35 && copies.inventory.items.count == 70)
        let kgRows = [["装备名称", "重量(kg)", "数量", "购买价格", "装备损坏", "状态"], ["测试帐篷", "1.5", "2", "￥1,200.50", "☑", "已购"], ["头灯", "待确认", "1", "", "☐", "已购"], ["", "", "", "", "", ""]]
        let kg = try ExcelImport.prepare(rows: kgRows, headerRow: 0, mapping: ExcelImport.mapping(kgRows[0]), into: Inventory(), update: true)
        precondition(kg.added == 2 && kg.warnings.count == 1)
        let gear = kg.inventory.items.first { $0.name == "测试帐篷" }!
        precondition(gear.weight == 1500 && gear.quantity == 2 && gear.purchasePrice == 1200.5 && gear.status == "损坏")
        var previous = result.inventory
        let index = previous.gear.firstIndex { $0.id == tent.id }!
        previous.gear[index].notes = "保留笔记"
        let partial = [["装备名称", "装备ID", "重量(g)"], ["更新名称", "EQ-001", "2100"]]
        let update = try ExcelImport.prepare(rows: partial, headerRow: 0, mapping: ExcelImport.mapping(partial[0]), into: previous, update: true)
        let updated = update.inventory.gear.first { $0.id == tent.id }!
        precondition(updated.notes == "保留笔记" && updated.purchasePrice == 619 && updated.weight == 2100)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExcelImportTests-" + UUID().uuidString)
        let store = GearStore(root: root)
        precondition(store.commitExcel(result))
        precondition(GearStore(root: root).inventory.items.count == 35)
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("导入前备份"), includingPropertiesForKeys: nil)
        precondition(backups.count == 1 && FileManager.default.fileExists(atPath: backups[0].appendingPathComponent("inventory.json").path))
        try FileManager.default.removeItem(at: root)
        print("PASS: actual six-sheet workbook; 35 rows; header detection; ID updates; ignored extra columns; kg/currency conversion; damage status; invalid-number warnings; preserved fields; automatic backup and persistence. Warnings: \(result.warnings.count)")
    }
}

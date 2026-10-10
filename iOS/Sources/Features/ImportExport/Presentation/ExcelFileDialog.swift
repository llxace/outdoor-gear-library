import AppKit
import UniformTypeIdentifiers

extension GearStore {
    func chooseExcel() -> ExcelImportSource? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!, UTType(filenameExtension: "xlsm")!]
        panel.message = "选择 .xlsx 或 .xlsm 表格。不会修改原表，也不会执行宏。旧 .xls 请先另存为 .xlsx。"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return ExcelImportSource(workbook: try ExcelWorkbook(url: url)) } catch {
            self.error = "Excel 读取失败：\(error.localizedDescription)"
            return nil
        }
    }
}

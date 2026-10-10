import Foundation

extension GearStore {

    func commitExcel(_ result: ExcelImportResult) -> Bool {
        do {
            let backupURL = try LibraryTransferFiles.backupDestination(in: root)
            try backup(to: backupURL)
            if commit(result.inventory) {
                notice = "Excel 导入完成：新增 \(result.added) 条、更新 \(result.updated) 条。导入前完整备份已保存在资料目录的“导入前备份”中。"
                return true
            }
        } catch { self.error = "无法保存导入前备份，已取消导入：\(error.localizedDescription)" }
        return false
    }
}

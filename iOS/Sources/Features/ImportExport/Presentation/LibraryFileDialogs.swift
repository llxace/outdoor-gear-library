import AppKit
import UniformTypeIdentifiers

extension GearStore {
    func choosePhoto() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        let name = UUID().uuidString + "." + source.pathExtension
        do {
            try LocalAssetFiles.copy(from: source, to: photoURL(name))
            return name
        } catch {
            self.error = "无法保存照片：\(error.localizedDescription)"
            return nil
        }
    }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "户外装备库.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try LibraryTransferFiles.exportCSV(inventory, to: url) } catch {
            self.error = "导出失败：\(error.localizedDescription)"
        }
    }
    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let next = try LibraryTransferFiles.importCSV(from: url, into: inventory)
            let alert = NSAlert()
            alert.messageText = "导入并更新装备库？"
            alert.informativeText = "按 Native.id 或 HB.import_ref 更新已有记录，没有标识的行会新增。照片和附件不受 CSV 更新影响；完整恢复请使用备份。"
            alert.addButton(withTitle: "导入")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if commit(next) { notice = "CSV / TSV 导入完成，已有标识的记录已更新。" }
        } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }
    func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "户外装备库备份.gearbackup"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try backup(to: destination)
            notice = "完整备份已保存，包含装备资料、装备清单、照片和附件。"
        } catch { self.error = "备份失败：\(error.localizedDescription)" }
    }
    func importBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择 .gearbackup 备份文件夹。恢复会合并，同一编号的记录以备份内容为准。"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard confirm("合并恢复这份备份？", "同编号记录会被替换，其他记录保留。位置、照片与附件一起恢复；资产编号冲突会重新编号。恢复前的数据保存在上一版文件中。") else { return }
        do { if try restore(from: source) { notice = "完整备份已恢复。" } } catch {
            self.error = "恢复失败，现有记录未修改：\(error.localizedDescription)"
        }
    }
}

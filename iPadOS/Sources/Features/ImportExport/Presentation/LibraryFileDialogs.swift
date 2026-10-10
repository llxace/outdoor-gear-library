import UIKit
import UniformTypeIdentifiers

extension GearStore {
    func choosePhoto(completion: @escaping (String?) -> Void) {
        PadFileDialog.pick([.image]) { result in
            do {
                guard let source = try result.get().first else { completion(nil); return }
                let name = UUID().uuidString + "." + source.pathExtension
                try LocalAssetFiles.copy(from: source, to: self.photoURL(name))
                completion(name)
            } catch { self.error = "无法保存照片：\(error.localizedDescription)"; completion(nil) }
        }
    }
    func exportCSV() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("户外装备库.csv")
        do { try LibraryTransferFiles.exportCSV(inventory, to: url); PadFileDialog.share(url) }
        catch { self.error = "导出失败：\(error.localizedDescription)" }
    }
    func importCSV() {
        PadFileDialog.pick([.commaSeparatedText, .plainText]) { result in
            do {
                guard let url = try result.get().first else { return }
                let next = try LibraryTransferFiles.importCSV(from: url, into: self.inventory)
                if self.commit(next) { self.notice = "CSV / TSV 导入完成，已有标识的记录已更新。" }
            } catch { self.error = "导入失败：\(error.localizedDescription)" }
        }
    }
    func exportBackup() {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("户外装备库.gearbackup")
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try backup(to: destination); PadFileDialog.share(destination)
            notice = "完整备份已准备好，包含装备资料、装备清单、照片和附件。"
        } catch { self.error = "备份失败：\(error.localizedDescription)" }
    }
    func importBackup() {
        PadFileDialog.pick([.folder]) { result in
            do {
                guard let source = try result.get().first else { return }
                PadFileDialog.confirm("合并恢复这份备份？", "同编号记录会被替换，其他记录保留。位置、照片与附件一起恢复；资产编号冲突会重新编号。") { accepted in
                    guard accepted else { return }
                    do { if try self.restore(from: source) { self.notice = "完整备份已恢复。" } }
                    catch { self.error = "恢复失败，现有记录未修改：\(error.localizedDescription)" }
                }
            } catch { self.error = "恢复失败，现有记录未修改：\(error.localizedDescription)" }
        }
    }
}

import AppKit

extension GearStore {
    func importAttachments() -> [GearAttachment] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        var result: [GearAttachment] = []
        do {
            for url in panel.urls {
                result.append(try GearAttachmentFiles.importFile(url, root: root))
            }
        } catch { self.error = "导入附件失败：\(error.localizedDescription)" }
        return result
    }

    func exportAttachment(_ attachment: GearAttachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.title
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try GearAttachmentFiles.exportFile(attachmentURL(attachment), to: url) } catch {
            self.error = "导出附件失败：\(error.localizedDescription)"
        }
    }
}

import UIKit
import UniformTypeIdentifiers

extension GearStore {
    func importAttachments(completion: @escaping ([GearAttachment]) -> Void) {
        PadFileDialog.pick([.item], multiple: true) { result in
            do {
                var imported: [GearAttachment] = []
                for url in try result.get() { imported.append(try GearAttachmentFiles.importFile(url, root: self.root)) }
                completion(imported)
            } catch { self.error = "导入附件失败：\(error.localizedDescription)"; completion([]) }
        }
    }
    func exportAttachment(_ attachment: GearAttachment) { PadFileDialog.share(attachmentURL(attachment)) }
}

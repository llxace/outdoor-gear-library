import UIKit
import UniformTypeIdentifiers

extension GearStore {
    func chooseExcel(completion: @escaping (ExcelImportSource?) -> Void) {
        PadFileDialog.pick([UTType(filenameExtension: "xlsx")!, UTType(filenameExtension: "xlsm")!]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { completion(nil); return }
                do { completion(ExcelImportSource(workbook: try ExcelWorkbook(url: url))) }
                catch { self.error = "Excel 读取失败：\(error.localizedDescription)"; completion(nil) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
                completion(nil)
            }
        }
    }
}

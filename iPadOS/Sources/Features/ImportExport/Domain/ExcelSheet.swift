import Foundation

struct ExcelSheet: Identifiable {
    let name: String
    let path: String
    var id: String { path }
}

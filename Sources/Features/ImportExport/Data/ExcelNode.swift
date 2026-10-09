import Foundation

final class ExcelNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [ExcelNode] = []
    init(_ name: String, _ attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
    func child(_ name: String) -> ExcelNode? { children.first { $0.name == name } }
    var content: String { text + children.map(\.content).joined() }
}

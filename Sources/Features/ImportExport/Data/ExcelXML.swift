import Foundation

final class ExcelXML: NSObject, XMLParserDelegate {
    var root: ExcelNode?
    private var stack: [ExcelNode] = []
    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        let node = ExcelNode(name.components(separatedBy: ":").last ?? name, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }
    static func parse(_ data: Data) throws -> ExcelNode {
        let delegate = ExcelXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = delegate.root else { throw ExcelWorkbook.failure("Excel XML 无法读取，文件可能损坏。") }
        return root
    }
}

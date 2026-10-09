import Foundation
import SwiftSyntax
import SwiftParser

final class FunctionVisitor: SyntaxVisitor {
    var functions = 0
    var failures: [String] = []
    let path: String
    init(path: String) {
        self.path = path
        super.init(viewMode: .sourceAccurate)
    }
    private func check(_ node: some SyntaxProtocol, name: String) {
        functions += 1
        let lines = node.trimmedDescription.components(separatedBy: .newlines).count
        if lines > 30 { failures.append("\(path): \(name) has \(lines) lines") }
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { check(node, name: node.name.text) }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, name: "init")
        return .visitChildren
    }
}

let sourceRoot = URL(fileURLWithPath: CommandLine.arguments[1])
let entries = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)!
var count = 0
var failures: [String] = []
for case let file as URL in entries where file.pathExtension == "swift" {
    let source = try String(contentsOf: file, encoding: .utf8)
    let visitor = FunctionVisitor(path: file.path.replacingOccurrences(of: sourceRoot.path + "/", with: ""))
    visitor.walk(Parser.parse(source: source))
    count += visitor.functions
    failures += visitor.failures
}
for failure in failures.sorted() { print(failure) }
print("\(count) functions and initializers; \(failures.count) exceed 30 lines")
exit(failures.isEmpty ? 0 : 1)

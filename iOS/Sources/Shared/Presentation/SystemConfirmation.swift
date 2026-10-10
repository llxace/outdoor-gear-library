import AppKit

func confirm(_ title: String, _ description: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = description
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")
    return alert.runModal() == .alertFirstButtonReturn
}

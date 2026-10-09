import Foundation
import AppKit
import SwiftUI

@main struct ThemeChecks {
    static func main() throws {
        precondition(GearAppearance.system.scheme == nil && GearAppearance.system.native == nil)
        precondition(GearAppearance.light.scheme == .light && GearAppearance.light.native?.name == .aqua)
        precondition(GearAppearance.dark.scheme == .dark && GearAppearance.dark.native?.name == .darkAqua)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearThemeTests-" + UUID().uuidString)
        let store = GearStore(root: root)
        var gear = Gear(); gear.name = "主题测试装备"
        precondition(store.save(gear))
        for mode in GearAppearance.allCases {
            var next = store.inventory; next.settings.appearance = mode.rawValue
            precondition(store.commit(next))
            let reopened = GearStore(root: root)
            precondition(reopened.inventory.settings.appearance == mode.rawValue && reopened.inventory.items.count == 1)
        }
        try FileManager.default.removeItem(at: root)
        print("PASS: system appearance inherits; light/dark override; all three modes persist without changing equipment")
    }
}

import SwiftUI
import AppKit

// 全应用共用的石墨灰与松绿配色；深浅外观维持同一色相。
enum GearDesign {
    static let background = adaptive("GearBackground", light: 0xF3F6F4, dark: 0x1C201F)
    static let surface = adaptive("GearSurface", light: 0xFFFFFF, dark: 0x252B28)
    static let selection = adaptive("GearSelection", light: 0xDCEBE3, dark: 0x30483E)
    static let accent = adaptive("GearAccent", light: 0x2C6651, dark: 0x91C7AE)
    // 深色外观的实心按钮用深松绿，确保浅色标题清晰；浅色模式用相同色相的中深绿。
    static let controls = adaptive("GearControls", light: 0x356C55, dark: 0x356C55)

    private static func adaptive(_ name: String, light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: Double((value >> 16) & 255) / 255,
                green: Double((value >> 8) & 255) / 255,
                blue: Double(value & 255) / 255,
                alpha: 1
            )
        })
    }
}

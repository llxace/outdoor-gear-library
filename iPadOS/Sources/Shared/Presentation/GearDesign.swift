import SwiftUI
import UIKit

// 全应用共用的石墨灰与松绿配色；深浅外观维持同一色相。
enum GearDesign {
    static let background = adaptive(light: 0xF3F6F4, dark: 0x1C201F)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x252B28)
    static let selection = adaptive(light: 0xDCEBE3, dark: 0x30483E)
    static let accent = adaptive(light: 0x2C6651, dark: 0x91C7AE)
    static let controls = adaptive(light: 0x356C55, dark: 0x356C55)
    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

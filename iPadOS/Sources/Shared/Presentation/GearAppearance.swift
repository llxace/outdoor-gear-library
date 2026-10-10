import SwiftUI
import UIKit

enum GearAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var explanation: String {
        switch self {
        case .system: return "随 iPadOS 自动切换浅色与深色，背景、文字和强调色一起适配。"
        case .light: return "固定使用浅色外观，不随系统切换。"
        case .dark: return "固定使用深色外观，不随系统切换。"
        }
    }
}

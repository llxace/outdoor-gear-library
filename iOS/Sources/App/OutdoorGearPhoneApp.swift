import SwiftUI
import UIKit

@main
struct OutdoorGearPhoneApp: App {
    @StateObject private var library = GearLibrary()

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(library)
                .preferredColorScheme(colorScheme)
                .tint(OutdoorPalette.accent)
        }
    }

    private var colorScheme: ColorScheme? {
        switch library.appearance {
        case "浅色": .light
        case "深色": .dark
        default: nil
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("概览", systemImage: "square.grid.2x2") }
            PackingView()
                .tabItem { Label("打包", systemImage: "checklist") }
            GearListView()
                .tabItem { Label("装备库", systemImage: "backpack") }
            NavigationStack { HikeHistoryView() }
                .tabItem { Label("徒步", systemImage: "figure.hiking") }
            DataView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
        }
    }
}

enum OutdoorPalette {
    static let forest = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.055, green: 0.105, blue: 0.082, alpha: 1) : UIColor(red: 0.94, green: 0.96, blue: 0.93, alpha: 1)
    })
    static let forestLight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.085, green: 0.15, blue: 0.112, alpha: 1) : UIColor(red: 0.97, green: 0.98, blue: 0.96, alpha: 1)
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.62, green: 0.78, blue: 0.45, alpha: 1) : UIColor(red: 0.22, green: 0.43, blue: 0.23, alpha: 1)
    })
    static let warm = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.91, green: 0.72, blue: 0.43, alpha: 1) : UIColor(red: 0.57, green: 0.34, blue: 0.10, alpha: 1)
    })
    static let glassTint = accent.opacity(0.13)
    static let background = LinearGradient(colors: [forest, forestLight, forest], startPoint: .topLeading, endPoint: .bottomTrailing)
}

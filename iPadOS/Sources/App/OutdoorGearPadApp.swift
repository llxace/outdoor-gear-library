import SwiftUI
import UIKit

@main
struct OutdoorGearPadApp: App {
    @StateObject private var libraries: UserLibraries
    init() {
        let root = LocalAssetFiles.libraryRoot
        _libraries = StateObject(wrappedValue: UserLibraries(root: root))
    }
    var body: some Scene {
        WindowGroup {
            NativeLibrary()
                .padFileDialogHost()
                .environmentObject(libraries.store)
                .environmentObject(libraries)
                .id(libraries.selectedID)
                .tint(GearDesign.accent)
                .preferredColorScheme(colorScheme)
        }
    }
    private var colorScheme: ColorScheme? {
        switch libraries.store.inventory.settings.appearance {
        case "浅色": .light
        case "深色": .dark
        default: nil
        }
    }
}

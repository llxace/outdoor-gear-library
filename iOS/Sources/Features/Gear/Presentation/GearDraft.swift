import SwiftUI
import AppKit

struct GearDraft: Identifiable {
    var id = UUID()
    var gear = Gear()
    var extras = GearExtras()
}

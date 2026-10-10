import SwiftUI
import UIKit

struct GearDraft: Identifiable {
    var id = UUID()
    var gear = Gear()
    var extras = GearExtras()
}

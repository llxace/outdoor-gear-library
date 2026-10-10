import SwiftUI
import UIKit

struct GearCategoryIcon: View {
    let name: String
    var body: some View {
        Group {
            if name == "袜子" {
                SockSymbol().fill(style: FillStyle(eoFill: true)).frame(width: 22, height: 24)
            } else {
                Image(systemName: GearSubcategories.symbol(for: name))
            }
        }.accessibilityHidden(true)
    }
}

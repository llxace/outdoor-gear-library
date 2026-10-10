import SwiftUI
import UIKit

struct PhotoRequest: Identifiable {
    let source: String
    var id: String { source }
}

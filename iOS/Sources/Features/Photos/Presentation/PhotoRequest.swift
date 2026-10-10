import SwiftUI
import AppKit

struct PhotoRequest: Identifiable {
    let source: String
    var id: String { source }
}

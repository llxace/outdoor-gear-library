import SwiftUI

struct DataCardStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.padding(16).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(DataCardStyle())
    }
}

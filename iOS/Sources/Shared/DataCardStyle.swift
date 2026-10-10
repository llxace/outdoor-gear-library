import SwiftUI

struct DataCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(DataCardStyle())
    }
}

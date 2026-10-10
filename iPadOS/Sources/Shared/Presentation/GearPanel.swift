import SwiftUI
import UIKit

struct GearPanel<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    Color(uiColor: .separator), lineWidth: contrast == .increased ? 1.5 : 0.5))
    }
}

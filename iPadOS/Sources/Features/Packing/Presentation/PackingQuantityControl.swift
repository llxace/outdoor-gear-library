import SwiftUI

struct PackingQuantityControl: View {
    let name: String
    let quantity: Double?
    let maximum: Double
    let change: (Double?) -> Void
    private var count: Double { quantity ?? 0 }
    private func set(_ value: Double) {
        guard value.isFinite else { return }
        let capped = max(0, min(maximum, value))
        change(capped == 0 ? nil : capped)
    }
    var body: some View {
        HStack(spacing: 6) {
            Button {
                set(count - 1)
            } label: {
                Image(systemName: "minus").frame(width: 16, height: 16).foregroundStyle(
                    count <= 0 ? Color.secondary : GearDesign.accent)
            }
            .disabled(count <= 0).accessibilityLabel("减少\(name)携带数量").help("减到 0 时取消选择")
            TextField("携带数量", value: Binding(get: { count }, set: set), format: .number)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .background(GearDesign.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                .accessibilityLabel("\(name)携带数量")
            Button {
                set(count + 1)
            } label: {
                Image(systemName: "plus").frame(width: 16, height: 16).foregroundStyle(
                    count >= maximum ? Color.secondary : GearDesign.accent)
            }
            .disabled(count >= maximum).accessibilityLabel("增加\(name)携带数量").help("最多 \(maximum.formatted()) 件；增加时自动选中")
        }.buttonStyle(.bordered).controlSize(.small).frame(width: 150)
    }
}

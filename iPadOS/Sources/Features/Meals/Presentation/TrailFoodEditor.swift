import SwiftUI
import UIKit

struct TrailFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: TrailFood
    let days: Int
    let currency: String
    let save: (TrailFood) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("路餐食物").font(.title2.bold())
            Form {
                TextField("食物名称", text: $draft.name)
                Picker("天数", selection: $draft.day) { ForEach(1...days, id: \.self) { Text("第\($0)天").tag($0) } }
                Picker("餐次", selection: $draft.meal) { ForEach(TrailFood.meals, id: \.self) { Text($0) } }
                TextField("携带总份数", value: $draft.quantity, format: .number)
                TextField("每份含包装重量（g）", value: $draft.grams, format: .number)
                TextField("每份热量（kcal）", value: $draft.calories, format: .number)
                Text("包装若标注 kJ，除以 4.184 转换为 kcal；每 100 g 数值须换算为本份。0 表示未填。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("每份价格（\(currency)）", value: $draft.price, format: .number)
                Picker("食用方式", selection: $draft.preparation) {
                    ForEach(TrailFood.preparations, id: \.self) { Text($0) }
                }
                TextField("备注（口味、过敏原、补给点等）", text: $draft.notes)
            }.formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { if save(draft) { dismiss() } }.disabled(!draft.isValid).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(maxWidth: 760, maxHeight: .infinity)
    }
}

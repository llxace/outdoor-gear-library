import SwiftUI
import UIKit

struct TrailMealSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: TrailMealPlan
    let save: (TrailMealPlan) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("路餐行程").font(.title2.bold())
            Form {
                DatePicker("出发日期", selection: $draft.startDate, displayedComponents: .date)
                Stepper("\(draft.days) 天", value: $draft.days, in: max(1, draft.foods.map(\.day).max() ?? 1)...60)
                Stepper("\(draft.people) 人", value: $draft.people, in: 1...100)
                TextField("每人每日热量目标（kcal，0 表示不设）", value: $draft.dailyGoal, format: .number)
                TextField("全队出发实际携水量（L）", value: $draft.waterLiters, format: .number)
                Text("减少天数前，请先调整对应日期的食物。携水重量按 1 L ≈ 1 kg 计入总负重，水瓶重量仍在装备中录入。")
                    .font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { if save(draft) { dismiss() } }.disabled(!draft.isValid).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(maxWidth: 760, maxHeight: .infinity)
    }
}

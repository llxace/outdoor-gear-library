import SwiftUI
import AppKit

struct TrailMealsView: View {
    @EnvironmentObject var store: GearStore
    @State private var foodDraft: TrailFood?
    @State private var configuring = false
    @State private var recommending = false
    @State private var scanning = false
    @State private var scannedDraft: TrailFood?
    @State private var day = 0
    private var plan: TrailMealPlan { store.inventory.mealPlan }
    private var visible: [TrailFood] { plan.foods.filter { day == 0 || $0.day == day }.sorted { $0.day < $1.day } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mealPlanHeading
            Text(
                "食物 \(plan.foodWeight.formatted()) g · 已录入热量 \(plan.calories.formatted()) kcal · 预算 \(store.money(plan.cost)) · 出发携水 \(plan.waterLiters.formatted()) L"
            )
            .font(.headline).monospacedDigit()
            mealFilters
            dailyEnergyOverview
            foodList
            Text("备用粮计入携带重量和总热量，不计入每日计划热量。未填重量或热量的食物按 0 统计；目标由你填写，不自动推算个人需求。饮水填写出发实际携带量，不代表全程用水需求。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12)
            .onChange(of: plan.days) { count in if day > count { day = 0 } }
            .sheet(
                isPresented: $scanning,
                onDismiss: {
                    if let scannedDraft {
                        foodDraft = scannedDraft
                        self.scannedDraft = nil
                    }
                }
            ) {
                FoodLabelScanner { result in
                    var food = TrailFood()
                    food.name = result.name
                    food.grams = result.grams ?? 0
                    food.calories = result.calories ?? 0
                    food.notes = "包装识别，请核对每份重量与热量"
                    food.day = max(1, day)
                    scannedDraft = food
                    scanning = false
                }
            }
            .sheet(item: $foodDraft) { food in
                TrailFoodEditor(draft: food, days: plan.days, currency: "CNY") { saved in
                    var next = plan
                    next.foods.removeAll { $0.id == saved.id }
                    next.foods.append(saved)
                    return store.saveMealPlan(next)
                }
            }
            .sheet(isPresented: $recommending) { TrailMealRecommendationView(plan: plan) { store.saveMealPlan($0) } }
            .sheet(isPresented: $configuring) { TrailMealSettings(draft: plan) { store.saveMealPlan($0) } }
    }
    private func flag(_ food: TrailFood, purchased: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let current = plan.foods.first { $0.id == food.id } ?? food
                return purchased ? current.purchased : current.packed
            },
            set: { value in
                var next = plan
                guard let index = next.foods.firstIndex(where: { $0.id == food.id }) else { return }
                if purchased { next.foods[index].purchased = value } else { next.foods[index].packed = value }
                _ = store.saveMealPlan(next)
            })
    }

    private var mealPlanHeading: some View {
        HStack {
            Label("路餐计划", systemImage: "fork.knife").font(.title3.bold())
            Stepper(
                "\(plan.days) 天",
                value: Binding(
                    get: { plan.days },
                    set: { count in
                        var next = plan
                        next.days = count
                        _ = store.saveMealPlan(next)
                    }), in: max(1, plan.foods.map(\.day).max() ?? 1)...60
            ).fixedSize()
            Text("\(plan.people) 人").foregroundStyle(.secondary)
            Spacer()
            Button("路餐推荐", systemImage: "sparkles") { recommending = true }
            Button("行程与目标") { configuring = true }
            Button("复制采购清单") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plan.shoppingList, forType: .string)
            }
            Button("拍照识别", systemImage: "camera") { scanning = true }
            Button("添加食物", systemImage: "plus") {
                var food = TrailFood()
                food.day = max(1, day)
                foodDraft = food
            }
        }
    }

    private var mealFilters: some View {
        HStack {
            Picker("查看", selection: $day) {
                Text("全部天数").tag(0)
                ForEach(1...plan.days, id: \.self) { Text("第\($0)天").tag($0) }
            }.frame(maxWidth: 220)
            Spacer()
            Text("数量填写所有人的携带总份数，热量和价格按每份填写。包装重量也计入每份重量。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var dailyEnergyOverview: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(1...plan.days, id: \.self) { number in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "第\(number)天 · "
                                + (Calendar.current.date(byAdding: .day, value: number - 1, to: plan.startDate)
                                ?? plan.startDate).formatted(.dateTime.month().day())
                        ).fontWeight(.semibold)
                        Text(
                            "\((plan.energy(day: number) / Double(plan.people)).formatted(.number.precision(.fractionLength(0)))) kcal / 人"
                        )
                        if plan.dailyGoal > 0 {
                            Text(
                                "目标 \(plan.dailyGoal.formatted()) · 差额 \(max(0, plan.dailyGoal - plan.energy(day: number) / Double(plan.people)).formatted())"
                            )
                        }
                    }.font(.caption).padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var foodList: some View {
        List {
            ForEach(visible) { food in
                HStack(spacing: 12) {
                    Image(systemName: food.meal == "备用粮" ? "cross.case" : "takeoutbag.and.cup.and.straw")
                        .foregroundStyle(GearDesign.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name).fontWeight(.medium)
                        Text("第\(food.day)天 · \(food.meal) · \(food.quantity.formatted()) 份 · \(food.preparation)")
                            .font(.caption).foregroundStyle(.secondary)
                        if !food.notes.isEmpty { Text(food.notes).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("\(food.weight.formatted()) g · \(food.energy.formatted()) kcal").monospacedDigit()
                    Toggle("已购", isOn: flag(food, purchased: true))
                    Toggle("已装包", isOn: flag(food, purchased: false))
                    Button("编辑") { foodDraft = food }
                    Button {
                        var next = plan
                        next.foods.removeAll { $0.id == food.id }
                        _ = store.saveMealPlan(next)
                    } label: {
                        Image(systemName: "trash")
                    }.help("移除这项食物")
                }.padding(.vertical, 6)
            }
        }.overlay {
            if visible.isEmpty {
                Text("还没有安排路餐\n添加食物，按包装标签填写每份重量和热量").multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }
}

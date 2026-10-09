import SwiftUI
import AppKit

struct TrailMealRecommendationView: View {
    let plan: TrailMealPlan
    let save: (TrailMealPlan) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var options: TrailMealRecommendationOptions
    @State private var preview: [TrailFood] = []
    init(plan: TrailMealPlan, save: @escaping (TrailMealPlan) -> Bool) {
        self.plan = plan
        self.save = save
        var options = TrailMealRecommendationOptions()
        options.days = plan.days
        options.people = plan.people
        options.dailyCalories = plan.dailyGoal > 0 ? plan.dailyGoal : 2500
        options.resupply = plan.days > 7
        options.carryDays = min(5, plan.days)
        _options = State(initialValue: options)
    }
    private var totalWeight: Double { preview.reduce(0) { $0 + $1.weight } }
    private var totalCalories: Double { preview.reduce(0) { $0 + $1.energy } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("路餐推荐", systemImage: "fork.knife").font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("按全程时长与补给段备餐。轻装／重装提供可修改的起始热量，不代表个人精确需求。").foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Stepper("全程 \(options.days) 天", value: $options.days, in: max(1, plan.foods.map(\.day).max() ?? 1)...60)
                Stepper("\(options.people) 人", value: $options.people, in: 1...100)
                Picker("负重模式", selection: $options.heavy) {
                    Text("轻装").tag(false)
                    Text("重装").tag(true)
                }.pickerStyle(.segmented).frame(width: 220)
            }
            HStack(spacing: 20) {
                Toggle("途中有已确认补给", isOn: $options.resupply)
                if options.resupply {
                    Stepper("从第 \(options.startDay) 天", value: $options.startDay, in: 1...options.days)
                    Stepper(
                        "携带 \(options.carriedDays) 天", value: $options.carryDays,
                        in: 1...max(1, options.days - options.startDay + 1))
                }
            }
            preparationOptions
            Text("常见长线每4–10天补给一次，并非安全上限。超过10天不补给时，应核对负重、食品保存和撤退方案；补给点需自行确认。").font(.caption).foregroundStyle(.secondary)
            if !options.isValid {
                Text("请填写有效的天数、人数和热量（1000–10000 kcal）。").foregroundStyle(.secondary)
            } else {
                Text(
                    "本次携带：第\(options.startDay)–\(options.endDay)天 · \(options.people)人 · 食物约 \((totalWeight / 1000).formatted(.number.precision(.fractionLength(2)))) kg · 含备用粮 \(totalCalories.formatted(.number.precision(.fractionLength(0)))) kcal"
                )
                .font(.headline).monospacedDigit()
                if options.resupply && options.endDay < options.days {
                    Text("仅加入本补给段的携带清单，第\(options.endDay + 1)天以后另行补给。饮水、燃料单独安排，不自动增加携水量。").font(.caption)
                        .foregroundStyle(.secondary)
                }
                recommendationPreview
            }
            Text("以上为可编辑的食物组合与营养估值，价格未填。加入后请用包装标签或拍照识别校准，并确认含坚果、奶、小麦等原料是否适合。已有食物会保留，重复餐次请调整。").font(.caption)
                .foregroundStyle(.secondary)
            recommendationActions
        }.padding(20).frame(width: 860, height: 690)
            .onAppear { preview = options.foods() }
            .onChange(of: options) { value in
                if value.startDay > value.days { options.startDay = value.days }
                if !value.resupply && value.startDay != 1 { options.startDay = 1 }
                if value.carryDays > value.days - value.startDay + 1 {
                    options.carryDays = max(1, value.days - value.startDay + 1)
                }
                preview = options.foods()
            }
            .onChange(of: options.heavy) { heavy in options.dailyCalories = heavy ? 3500 : 2500 }
    }

    private var preparationOptions: some View {
        HStack(spacing: 20) {
            Toggle("可以烧热水", isOn: $options.canHeat)
            Toggle("加1天备用粮", isOn: $options.reserve)
            Spacer()
            Text("每日目标／人")
            TextField("kcal", value: $options.dailyCalories, format: .number).textFieldStyle(.roundedBorder).frame(
                width: 90)
            Text("kcal")
        }
    }

    private var recommendationPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(preview) { food in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第\(food.day)天 · \(food.meal) · \(food.name)").fontWeight(.medium)
                            Text("\(food.quantity.formatted())人份 · \(food.preparation)").font(.caption).foregroundStyle(
                                .secondary)
                        }
                        Spacer()
                        Text(
                            "\(food.weight.formatted(.number.precision(.fractionLength(0)))) g · \(food.energy.formatted(.number.precision(.fractionLength(0)))) kcal"
                        ).monospacedDigit()
                    }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var recommendationActions: some View {
        HStack {
            Link("路餐参考 · REI", destination: URL(string: "https://www.rei.com/learn/expert-advice/planning-menu.html")!)
            Link(
                "长线补给 · PCTA",
                destination: URL(
                    string: "https://www.pcta.org/discover-the-trail/thru-hiking-long-distance-hiking/resupply/")!)
            Spacer()
            Button("加入本次路餐") {
                var next = plan
                next.days = options.days
                next.people = options.people
                next.dailyGoal = options.dailyCalories
                next.foods.append(contentsOf: preview)
                if save(next) { dismiss() }
            }.buttonStyle(.borderedProminent).disabled(!options.isValid || preview.isEmpty).keyboardShortcut(
                .defaultAction)
        }
    }
}

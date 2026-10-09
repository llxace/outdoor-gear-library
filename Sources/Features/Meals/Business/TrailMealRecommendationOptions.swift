import Foundation

struct TrailMealRecommendationOptions: Equatable {
    var days = 1
    var people = 1
    var heavy = false
    var canHeat = false
    var resupply = false
    var carryDays = 1
    var startDay = 1
    var dailyCalories = 2500.0
    var reserve = true
    var carriedDays: Int { min(carryDays, days - startDay + 1) }
    var endDay: Int { startDay + (resupply ? carriedDays : days - startDay + 1) - 1 }
    var isValid: Bool {
        (1...60).contains(days) && (1...100).contains(people) && (1...days).contains(startDay)
            && (1...60).contains(carryDays) && dailyCalories.isFinite && (1000...10000).contains(dailyCalories)
    }
    func foods() -> [TrailFood] {
        guard isValid else { return [] }
        let ratio = dailyCalories / templates.reduce(0) { $0 + $1.3 }
        var result: [TrailFood] = []
        for day in startDay...endDay {
            for template in templates {
                var food = TrailFood()
                food.name = template.0
                food.day = day
                food.meal = template.1
                food.quantity = Double(people)
                food.grams = template.2 * ratio + 5
                food.calories = template.3 * ratio
                food.preparation = template.4
                food.notes = "推荐示例估值，每份为1人份；含估计包装5g。按实际包装核对重量、热量和价格；按口味及过敏原替换。"
                result.append(food)
            }
        }
        if reserve { result.append(reserveFood()) }
        return result
    }
    private func reserveFood() -> TrailFood {
        var food = TrailFood()
        food.name = "备用即食粮（坚果、能量棒、饼干）"
        food.day = startDay
        food.meal = "备用粮"
        food.quantity = Double(people)
        food.grams = dailyCalories / 4.4 + 10
        food.calories = dailyCalories
        food.notes = "约1天／人的应急储备，示例估值含包装；不计入每日计划热量。请按实际食品标签核对。"
        return food
    }
    private var templates: [(String, String, Double, Double, String)] {
        return [
            (canHeat ? "燕麦与奶粉组合" : "即食麦片与奶粉组合", "早餐", 120, 520, canHeat ? "热水冲泡" : "即食"),
            ("饼干／卷饼与坚果酱组合", "午餐", 140, 600, "即食"),
            (
                canHeat ? "速食主食与脱水菜肉组合" : "即食饼干与肉干组合", "晚餐", canHeat ? 140 : 160, canHeat ? 600 : 650,
                canHeat ? "热水冲泡" : "即食"
            ),
            ("混合坚果", "行进零食", 80, 480, "即食"),
            ("果干", "行进零食", 60, 180, "即食"),
            ("巧克力／能量棒", "行进零食", 40, 220, "即食"),
        ]
    }
}

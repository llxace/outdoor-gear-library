import Foundation

struct TrailMealPlan: Codable, Equatable {
    var startDate = Date()
    var days = 1
    var people = 1
    var dailyGoal = 0.0
    var waterLiters = 0.0
    var foods: [TrailFood] = []
    var foodWeight: Double { foods.reduce(0) { $0 + $1.weight } }
    var totalWeight: Double { foodWeight + waterLiters * 1000 }
    var calories: Double { foods.reduce(0) { $0 + $1.energy } }
    var cost: Double { foods.reduce(0) { $0 + $1.cost } }
    func energy(day: Int) -> Double { foods.filter { $0.day == day && $0.meal != "备用粮" }.reduce(0) { $0 + $1.energy } }
    var isValid: Bool {
        (1...60).contains(days) && (1...100).contains(people) && startDate.timeIntervalSince1970.isFinite
            && [dailyGoal, waterLiters, totalWeight, calories, cost].allSatisfy { $0.isFinite && $0 >= 0 }
            && foods.allSatisfy { $0.isValid && $0.day <= days } && Set(foods.map(\.id)).count == foods.count
    }
    var shoppingList: String {
        let rows = foods.sorted { $0.day < $1.day }.map {
            "\($0.purchased ? "已购" : "待购") · 第\($0.day)天 \($0.meal) · \($0.name) × \($0.quantity.formatted()) · \($0.weight.formatted()) g · \($0.preparation)"
                + ($0.notes.isEmpty ? "" : " · " + $0.notes)
        }
        return
            (["路餐清单 · \(days) 天 · \(people) 人", "食物 \(foodWeight.formatted()) g · 出发携水 \(waterLiters.formatted()) L"]
            + rows).joined(separator: "\n")
    }
}

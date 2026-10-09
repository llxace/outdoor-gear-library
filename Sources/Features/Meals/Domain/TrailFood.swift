import Foundation

struct TrailFood: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var day = 1
    var meal = "行进零食"
    var quantity = 1.0
    var grams = 0.0
    var calories = 0.0
    var price = 0.0
    var preparation = "即食"
    var notes = ""
    var purchased = false
    var packed = false
    static let meals = ["早餐", "午餐", "晚餐", "行进零食", "备用粮"]
    static let preparations = ["即食", "热水冲泡", "需要烹煮"]
    var weight: Double { quantity * grams }
    var energy: Double { quantity * calories }
    var cost: Double { quantity * price }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && day >= 1 && day <= 60
            && Self.meals.contains(meal) && Self.preparations.contains(preparation) && quantity.isFinite && quantity > 0
            && [grams, calories, price, weight, energy, cost].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

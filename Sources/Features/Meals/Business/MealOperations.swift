import Foundation

enum MealOperations {
    static func saveMealPlan(_ plan: TrailMealPlan, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.mealPlan = plan
        return next
    }
}

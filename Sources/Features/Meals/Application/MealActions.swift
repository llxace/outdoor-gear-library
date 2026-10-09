import Foundation

extension GearStore {
    @discardableResult func saveMealPlan(_ plan: TrailMealPlan) -> Bool {
        return updateInventory { try MealOperations.saveMealPlan(plan, in: $0) }
    }
}

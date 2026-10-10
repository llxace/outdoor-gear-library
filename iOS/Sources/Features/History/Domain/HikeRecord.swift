import Foundation

struct HikeRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var date = Date()
    var routeName = ""
    var distance = ""
    var notes = ""
    var route: HikingRoute?
    var gear: [HikeGear] = []
    var mealPlan: TrailMealPlan?
    var deleted = false
    var weight: Double { gear.reduce(0) { $0 + $1.gear.weight * $1.quantity } }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && date.timeIntervalSince1970.isFinite
            && gear.allSatisfy(\.isValid) && Set(gear.map(\.id)).count == gear.count && weight.isFinite
            && (route?.isValid ?? true) && (mealPlan?.isValid ?? true)
    }
}

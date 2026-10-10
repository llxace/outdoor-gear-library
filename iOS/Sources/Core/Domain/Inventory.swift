import Foundation

struct Inventory: Codable {
    var version = 9
    var gear: [Gear] = []
    var favoriteGearIDs: [UUID] = []
    var packingItems: [PackingItem] = []
    var borrowedPackingItems: [BorrowedPackingItem] = []
    var hikeHistory: [HikeRecord] = []
    var selectedRoute: HikingRoute?
    var mealPlan = TrailMealPlan()
    var locations: [String] = []
    static let outdoorCategories = ["背包与收纳", "帐篷与睡眠", "服装与配饰", "鞋袜与行走", "炊具与饮水", "照明与电子", "工具与急救", "洗漱与杂项"]
    var categories = Inventory.outdoorCategories
    var details: [String: GearExtras] = [:]
    var labels: [GearTag] = []
    var templates: [GearTemplate] = []
    var settings = LibrarySettings()
    init() {}
    enum CodingKeys: String, CodingKey {
        case version, gear, favoriteGearIDs, packingItems, borrowedPackingItems, hikeHistory, selectedRoute, mealPlan,
            locations, categories, details, labels, templates, settings
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        gear = try c.decode([Gear].self, forKey: .gear)
        favoriteGearIDs = try c.decodeIfPresent([UUID].self, forKey: .favoriteGearIDs) ?? []
        packingItems = try c.decodeIfPresent([PackingItem].self, forKey: .packingItems) ?? []
        borrowedPackingItems = try c.decodeIfPresent([BorrowedPackingItem].self, forKey: .borrowedPackingItems) ?? []
        hikeHistory = try c.decodeIfPresent([HikeRecord].self, forKey: .hikeHistory) ?? []
        selectedRoute = try c.decodeIfPresent(HikingRoute.self, forKey: .selectedRoute)
        mealPlan = try c.decodeIfPresent(TrailMealPlan.self, forKey: .mealPlan) ?? TrailMealPlan()
        locations = try c.decode([String].self, forKey: .locations)
        categories = try c.decode([String].self, forKey: .categories)
        details = try c.decodeIfPresent([String: GearExtras].self, forKey: .details) ?? [:]
        labels = try c.decodeIfPresent([GearTag].self, forKey: .labels) ?? []
        templates = try c.decodeIfPresent([GearTemplate].self, forKey: .templates) ?? []
        settings = try c.decodeIfPresent(LibrarySettings.self, forKey: .settings) ?? LibrarySettings()
    }
    func isFavorite(_ id: UUID) -> Bool { favoriteGearIDs.contains(id) }
}

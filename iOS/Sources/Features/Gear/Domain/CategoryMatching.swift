import Foundation

extension Inventory {
    func matchesCategoryFolder(_ gear: Gear, path: String) -> Bool {
        if path == "全部分类" { return true }
        if path == "已损坏" { return gear.status == "损坏" }
        let parts = path.split(separator: "/").map(String.init)
        guard let parent = parts.first, gear.category == parent else { return false }
        return parts.count == 1 || subcategory(for: gear) == parts[1]
    }
    func subcategory(for gear: Gear) -> String {
        GearSubcategories.resolved(for: gear, stored: extras(gear.id).subcategory)
    }
}

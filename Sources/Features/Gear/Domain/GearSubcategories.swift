import Foundation

// 子分类只负责浏览与录入，不改变装备归属、携带数量或重量。
enum GearSubcategories {
    static func children(of category: String) -> [String] {
        switch category {
        case "帐篷与睡眠": return ["帐篷", "睡袋", "防潮垫与睡眠配件"]
        case "服装与配饰": return ["贴身与速干", "抓绒与中层", "羽绒与棉服", "防风与雨衣", "裤装", "帽子与头巾", "手套", "眼镜与面罩", "其他服装"]
        case "鞋袜与行走": return ["鞋", "袜子", "行走配件"]
        default: return []
        }
    }
    static func inferred(for gear: Gear) -> String {
        let name = (gear.name + " " + gear.model).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { name.contains($0) } }
        switch gear.category {
        case "帐篷与睡眠":
            if has(["帐篷", "天幕", "tent"]) { return "帐篷" }
            if has(["睡袋", "sleeping bag"]) { return "睡袋" }
            return "防潮垫与睡眠配件"
        case "鞋袜与行走":
            if has(["袜", "sock"]) { return "袜子" }
            if has(["鞋", "靴", "shoe", "boot"]) { return "鞋" }
            return "行走配件"
        case "服装与配饰":
            return clothingCategory(matching: has)
        default: return ""
        }
    }
    private static func clothingCategory(matching has: ([String]) -> Bool) -> String {
        if has(["手套", "glove", "mitten"]) { return "手套" }
        if has(["风镜", "眼镜", "面罩", "护目", "goggle", "sunglass", "mask"]) { return "眼镜与面罩" }
        if has(["围巾", "头巾", "脖套", "beanie", "brimmer", "scarf", "buff"])
            || (has(["帽", "hat"]) && !has(["外套", "夹克", "衣", "jacket", "coat", "hoodie"]))
        {
            return "帽子与头巾"
        }
        // 裤装先于面料、保暖和防水词，避免罩裤或羽绒裤被归为上衣。
        if has(["内裤", "内衣", "贴身", "dotknit", "base layer", "underwear"]) { return "贴身与速干" }
        if has(["裤", "pant", "trouser"]) { return "裤装" }
        if has(["羽绒", "棉服", "棉衣", "化纤保暖", "ventrix", "50/50", "cloud down", "parka", "down jacket", "insulated"]) {
            return "羽绒与棉服"
        }
        if has(["抓绒", "fleece", "polartec"]) { return "抓绒与中层" }
        if has([
            "硬壳", "冲锋衣", "雨衣", "防晒外套", "防晒外壳", "防风", "futurelight", "sangro", "shell", "rain jacket", "windbreaker",
        ]) {
            return "防风与雨衣"
        }
        if has(["速干", "美利奴", "长袖t", "t恤", "短袖", "merino", "tee", "t-shirt"]) { return "贴身与速干" }
        return "其他服装"
    }
    static func resolved(for gear: Gear, stored: String?) -> String {
        guard let stored else { return inferred(for: gear) }
        if children(of: gear.category).contains(stored) { return stored }
        guard gear.category == "服装与配饰" else { return inferred(for: gear) }
        switch stored {
        case "贴身层": return "贴身与速干"
        case "中间层": return "抓绒与中层"
        case "活动保暖层", "外层保暖层": return "羽绒与棉服"
        case "防护外层": return inferred(for: gear) == "裤装" ? "裤装" : "防风与雨衣"
        default: return inferred(for: gear)
        }
    }
    static func symbol(for name: String) -> String {
        switch name {
        case "背包与收纳": return "backpack.fill"
        case "帐篷与睡眠", "帐篷": return "tent.fill"
        case "睡袋": return "bed.double.fill"
        case "防潮垫与睡眠配件": return "rectangle.split.3x1.fill"
        case "服装与配饰", "贴身与速干": return "tshirt.fill"
        case "抓绒与中层": return "square.3.layers.3d"
        case "防风与雨衣": return "shield.lefthalf.filled"
        case "羽绒与棉服": return "snowflake"
        case "裤装": return "figure.walk"
        case "帽子与头巾": return "sun.max.fill"
        case "手套": return "hand.raised.fill"
        case "眼镜与面罩": return "eyeglasses"
        case "其他服装": return "hanger"
        case "鞋袜与行走", "鞋": return "shoe.2.fill"
        case "行走配件": return "figure.hiking"
        case "炊具与饮水": return "fork.knife"
        case "照明与电子": return "flashlight.on.fill"
        case "工具与急救": return "cross.case.fill"
        case "洗漱与杂项": return "hands.sparkles.fill"
        case "已损坏": return "exclamationmark.triangle.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}

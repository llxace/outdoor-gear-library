import Foundation

extension Inventory {
    @discardableResult mutating func organizeOutdoorCategories() -> Bool {
        var changed = categories != Self.outdoorCategories
        categories = Self.outdoorCategories
        for i in gear.indices where !extras(gear[i].id).isLocation {
            let source = gear[i].category.trimmingCharacters(in: .whitespacesAndNewlines)
            let category: String
            switch source {
            case "背包", "登山包", "收纳包", "防水袋", "腰包", "压缩袋": category = "背包与收纳"
            case "帐篷", "防潮垫", "睡袋", "睡袋内胆", "地布", "枕头", "天幕": category = "帐篷与睡眠"
            case "服装", "硬壳/冲锋衣", "贴身层", "抓绒", "徒步裤", "保暖层", "眼部防护", "遮阳帽",
                "硬壳/防水裤", "雨衣", "防晒面罩", "速干长袖", "针织帽", "手套", "防晒外壳":
                category = "服装与配饰"
            case "鞋袜", "雪套", "徒步鞋", "重装徒步鞋", "登山杖", "袜子", "冰爪": category = "鞋袜与行走"
            case "炊具", "饮水", "水壶", "水袋", "滤水器", "炉头", "锅具", "餐具", "燃料": category = "炊具与饮水"
            case "照明", "头灯", "营灯", "手机云台", "充电宝", "电池", "Electronics", "IOT": category = "照明与电子"
            case "应急毯", "急救包", "维修工具", "刀具", "导航", "指南针", "卫星通信": category = "工具与急救"
            default: category = Self.outdoorCategories.contains(source) ? source : "洗漱与杂项"
            }
            guard gear[i].category != category else { continue }
            gear[i].category = category
            changed = true
        }
        return changed
    }
}

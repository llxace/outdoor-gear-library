import Foundation

enum EquipmentStatistic: String, CaseIterable, Identifiable {
    case categoryQuantity = "分类数量"
    case brandQuantity = "品牌数量"
    case categoryWeight = "分类重量"
    case categoryCost = "分类支出"
    case brandCost = "品牌支出"
    var id: String { rawValue }
    var isWeight: Bool { self == .categoryWeight }
    var isCost: Bool { self == .categoryCost || self == .brandCost }
    var explanation: String {
        if isWeight { return "重量 = 单件重量 × 库内数量；单位 kg。" }
        if isCost { return "按记录购买总价相加，不再乘数量。" }
        return "按库内数量相加；单位件。"
    }
    func formatted(_ value: Double, currency: String) -> String {
        if isCost { return value.formatted(.currency(code: currency).precision(.fractionLength(0...2))) }
        return value.formatted(.number.precision(.fractionLength(0...3))) + (isWeight ? " kg" : " 件")
    }
    func distribution(_ gear: [Gear]) -> [Distribution] {
        var totals: [String: Double] = [:]
        for item in gear {
            let label: String
            switch self {
            case .brandQuantity, .brandCost: label = item.brand
            default: label = item.category
            }
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: Double
            if isWeight {
                value = item.weight * item.quantity / 1000
            } else if isCost {
                value = item.purchasePrice
            } else {
                value = item.quantity
            }
            totals[name.isEmpty ? "未填写" : name, default: 0] += value
        }
        return totals.map { Distribution(name: $0.key, value: $0.value) }.sorted {
            $0.value == $1.value ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.value > $1.value
        }
    }
}

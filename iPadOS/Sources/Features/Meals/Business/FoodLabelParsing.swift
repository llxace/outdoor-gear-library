import Foundation

extension FoodLabelResult {
    static func parse(_ text: String) -> FoodLabelResult {
        func groups(_ pattern: String) -> [String]? { Self.groups(pattern, in: text) }
        var result = FoodLabelResult()
        if let name = groups("(?:品名|产品名称|食品名称|名称)\\s*[:：]?\\s*([^\\n]+)") {
            result.name = name[0].trimmingCharacters(in: .whitespaces)
        }
        if let mass = groups("(?:净含量|净重|net\\s*weight)\\s*[:：]?\\s*(\\d+(?:\\.\\d+)?)\\s*(kg|千克|g|克)") {
            if let number = Double(mass[0]) {
                result.grams = number * (["kg", "千克"].contains(mass[1].lowercased()) ? 1000 : 1)
            }
        }
        if let energy = groups("(?:能量|热量|energy|calories)\\s*[:：]?\\s*(\\d+(?:\\.\\d+)?)\\s*(kcal|千卡|大卡|kj|千焦)") {
            if let number = Double(energy[0]) {
                let kcal = ["kj", "千焦"].contains(energy[1].lowercased()) ? number / 4.184 : number
                if groups("(每\\s*100\\s*(?:g|克)|per\\s*100\\s*g)") != nil, let grams = result.grams {
                    result.calories = kcal * grams / 100
                    result.message = "能量按每 100 g 换算为整包；净重不含包装，请补齐包装重量并核对每包是否算一份。"
                } else if groups("(每份|per\\s*serving)") != nil {
                    result.calories = kcal
                    result.message = "识别为每份能量；净含量可能是整包重量，请核对一份对应的重量。"
                } else {
                    result.message = "检测到能量值，但无法确认是每份还是每 100 g，暂不自动填入热量。"
                }
            }
        }
        if result.message.isEmpty { result.message = "未能完整识别营养信息，请核对文字并手动补齐。" }
        return result
    }
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

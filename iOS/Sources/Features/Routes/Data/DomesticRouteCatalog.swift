import Foundation

actor DomesticRouteCatalog {
    static let shared = DomesticRouteCatalog()

    private struct Package: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let route: HikingRoute
        let aliases: [String]
    }

    private var entries: [Entry]?

    func search(_ query: String) -> [HikingRoute] {
        guard let entries = try? load() else { return [] }
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }
        return entries.compactMap { entry -> (HikingRoute, Int)? in
            let score = ([entry.route.name, entry.route.area] + entry.aliases)
                .compactMap { matchScore(needle, in: normalize($0)) }
                .min()
            return score.map { (entry.route, $0) }
        }
        .sorted { $0.1 == $1.1 ? $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending : $0.1 < $1.1 }
        .map(\.0)
    }

    func routes(near point: TrailPoint, radius: Int) -> [HikingRoute] {
        guard let entries = try? load() else { return [] }
        let limit = Double(radius) * 1000
        return entries.compactMap { entry -> (HikingRoute, Double)? in
            let distance = entry.route.segments.flatMap { $0 }.map { meters(from: point, to: $0) }.min() ?? .infinity
            return distance <= limit ? (entry.route, distance) : nil
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private func load() throws -> [Entry] {
        if let entries { return entries }
        guard let url = Bundle.main.url(forResource: "DomesticRoutes", withExtension: "json") else {
            throw NSError(
                domain: "DomesticRouteCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到内置徒步路线数据。"])
        }
        let package = try JSONDecoder().decode(Package.self, from: Data(contentsOf: url))
        entries = package.entries
        return package.entries
    }

    private func normalize(_ value: String) -> String {
        let cleaned = String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        // The local catalog includes Traditional Chinese names for Hong Kong trails.
        // Normalize common trail-name characters so Simplified searches work too.
        let variants: [Character: Character] = [
            "麥": "麦", "徑": "径", "環": "环", "鳳": "凤", "龍": "龙", "島": "岛",
            "灣": "湾", "東": "东", "門": "门", "風": "风", "雲": "云", "觀": "观",
            "廟": "庙", "萬": "万", "長": "长", "樂": "乐", "園": "园", "區": "区",
            "樹": "树", "線": "线", "經": "经", "後": "后", "頭": "头",
            "峽": "峡", "壩": "坝", "橋": "桥", "場": "场", "壯": "壮", "馬": "马",
            "濕": "湿", "廢": "废", "嶼": "屿",
        ]
        return String(cleaned.map { variants[$0] ?? $0 })
    }

    /// Returns a relevance score for exact/partial, omitted-character, and typo-tolerant matches.
    private func matchScore(_ needle: String, in candidate: String) -> Int? {
        guard !needle.isEmpty, !candidate.isEmpty else { return nil }
        if candidate.contains(needle) { return 0 }

        let query = Array(needle)
        let text = Array(candidate)
        // A shortened query may skip one or two characters while keeping their order.
        if query.count >= 3, let gaps = subsequenceGapCount(query, in: text), gaps <= 2 {
            return 10 + gaps
        }

        // Allow a small typo in longer names. Compare against sliding windows so a
        // query can still find one section within a longer route title.
        guard query.count >= 3 else { return nil }
        let tolerance = max(1, query.count / 5)
        let lower = max(1, query.count - tolerance)
        let upper = min(text.count, query.count + tolerance)
        guard lower <= upper else { return nil }
        var best: Int?
        for length in lower...upper where length <= text.count {
            for start in 0...(text.count - length) {
                let distance = editDistance(query, Array(text[start..<(start + length)]), limit: tolerance)
                if distance <= tolerance, best == nil || distance < best! { best = distance }
            }
        }
        return best.map { 100 + $0 }
    }

    private func subsequenceGapCount(_ query: [Character], in text: [Character]) -> Int? {
        var cursor = 0
        var first = -1
        var last = -1
        for character in query {
            guard let index = text[cursor...].firstIndex(of: character) else { return nil }
            if first == -1 { first = index }
            last = index
            cursor = index + 1
        }
        return last - first + 1 - query.count
    }

    private func editDistance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            var rowMinimum = current[0]
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(min(current[j] + 1, previous[j + 1] + 1), previous[j] + (left == right ? 0 : 1))
                rowMinimum = min(rowMinimum, current[j + 1])
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[rhs.count]
    }

    private func meters(from a: TrailPoint, to b: TrailPoint) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 6_371_008.8 * 2 * asin(sqrt(min(1, h)))
    }
}

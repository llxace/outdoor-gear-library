import Foundation

struct ExchangeRateRepository {
    let root: URL
    private var cache: URL { root.appendingPathComponent("exchange-rates.json") }

    func cachedRates() -> [String: ExchangeRate] {
        guard let data = try? Data(contentsOf: cache),
            let rows = try? JSONDecoder().decode([ExchangeRate].self, from: data)
        else { return [:] }
        return Dictionary(
            rows.filter { $0.base == "CNY" && $0.rate.isFinite && $0.rate > 0 }
                .map { ($0.quote, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func fetch() async throws -> (rates: [String: ExchangeRate], data: Data) {
        var request = URLRequest(
            url: URL(string: "https://api.frankfurter.dev/v2/rates?base=CNY&quotes=USD,EUR,GBP,JPY,HKD,TWD")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder().decode([ExchangeRate].self, from: data)
        guard !rows.isEmpty, rows.allSatisfy({ $0.base == "CNY" && $0.rate.isFinite && $0.rate > 0 }) else {
            throw URLError(.cannotParseResponse)
        }
        return (Dictionary(rows.map { ($0.quote, $0) }, uniquingKeysWith: { _, latest in latest }), data)
    }

    func save(_ data: Data) throws { try data.write(to: cache, options: .atomic) }
}

import Foundation

extension GearStore {
    var displayCurrency: String { currency == "CNY" || exchangeRates[currency] != nil ? currency : "CNY" }
    func convertedMoney(_ yuan: Double) -> Double { yuan * (exchangeRates[displayCurrency]?.rate ?? 1) }
    func money(_ yuan: Double) -> String { convertedMoney(yuan).formatted(.currency(code: displayCurrency)) }
    var exchangeDescription: String {
        if currency == "CNY" { return "金额以人民币保存；切换货币自动按最新参考汇率显示。" }
        if let rate = exchangeRates[currency] {
            return
                "1 CNY = \(rate.rate.formatted(.number.precision(.fractionLength(2...6)))) \(currency) · 汇率日期 \(rate.date) · Frankfurter"
                + (exchangeError.isEmpty ? "" : " · 离线缓存")
        }
        return exchangeLoading ? "正在获取汇率，暂以人民币显示…" : "汇率不可用，暂以人民币显示。"
    }
    @MainActor func refreshExchangeRates() async {
        guard currency != "CNY", !exchangeLoading else { return }
        exchangeLoading = true
        exchangeError = ""
        defer { exchangeLoading = false }
        do {
            let repository = ExchangeRateRepository(root: root)
            let (next, data) = try await repository.fetch()
            guard next[currency] != nil || currency == "CNY" else { throw URLError(.cannotParseResponse) }
            exchangeRates = next
            try repository.save(data)
        } catch { exchangeError = "联网获取失败，使用缓存；没有缓存时保留人民币显示。" }
    }
}

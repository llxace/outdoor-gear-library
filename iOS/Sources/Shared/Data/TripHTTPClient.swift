import Foundation

enum TripHTTPClient {
    private static let agent = "OutdoorGearNative/0.11.0 (local.llxace.outdoorgear.native)"
    static func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw failure(code == 429 ? "在线服务繁忙，请稍后重试。" : "在线服务暂不可用（\(code)），请稍后重试。")
        }
        return data
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

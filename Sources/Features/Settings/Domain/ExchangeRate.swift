import Foundation

struct ExchangeRate: Codable {
    let date: String
    let base: String
    let quote: String
    let rate: Double
}

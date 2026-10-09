import Foundation

struct WeatherDay: Identifiable {
    let id: String
    let code: Int
    let low: Double
    let high: Double
    let rainChance: Double
    let rain: Double
    let wind: Double
    var conditions: (String, String) { weatherConditions(code) }
}

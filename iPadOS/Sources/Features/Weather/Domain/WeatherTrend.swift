import Foundation

struct WeatherTrend: Identifiable {
    let id: String
    let end: String
    let monthly: Bool
    let temperature: Double
    let temperatureAnomaly: Double
    let precipitationAnomaly: Double
    var wind: Double? = nil
    var cloudCover: Double? = nil
    var period: String { monthly ? String(id.prefix(7)) : String(id.suffix(5)) + "–" + String(end.suffix(5)) }
}

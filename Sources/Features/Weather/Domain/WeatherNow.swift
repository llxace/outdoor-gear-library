import Foundation

struct WeatherNow: Decodable {
    let time: String
    let temperature_2m: Double
    let apparent_temperature: Double
    let weather_code: Int
    var conditions: (String, String) { weatherConditions(weather_code) }
}

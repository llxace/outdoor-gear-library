import Foundation

protocol TripWeatherProviding {
    func forecast(latitude: Double, longitude: Double, date: Date) async throws -> TripWeather
}

struct OpenMeteoWeatherService: TripWeatherProviding {
    func forecast(latitude: Double, longitude: Double, date: Date) async throws -> TripWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let forecast = try JSONDecoder().decode(TripWeather.self, from: data)
        guard forecast.day(on: date) != nil else { throw WeatherRangeError.outsideForecast }
        return forecast
    }
}

enum WeatherRangeError: LocalizedError {
    case outsideForecast
    var errorDescription: String? { "所选出发日期超出 16 天天气预报范围。" }
}

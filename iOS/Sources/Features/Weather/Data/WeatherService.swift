import Foundation

@MainActor enum WeatherService {
    static func forecast(at point: TrailPoint, departure: Date = Date()) async throws -> WeatherForecast {
        guard departure.timeIntervalSince1970.isFinite else { throw failure("出发时间无效。") }
        let response = try await requestForecast(at: point)
        return try forecast(response, departure: departure)
    }
    nonisolated static func decodeForecast(_ data: Data, departure: Date) throws -> WeatherForecast {
        guard departure.timeIntervalSince1970.isFinite else { throw failure("出发时间无效。") }
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return try forecast(response, departure: departure)
    }
    nonisolated private static func forecast(_ response: ForecastResponse, departure: Date) throws -> WeatherForecast {
        let days = try forecastDays(response)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone =
            TimeZone(identifier: response.timezone) ?? TimeZone(secondsFromGMT: response.utc_offset_seconds)
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: departure)
        guard let first = days.first, let last = days.last, start >= first.id, start <= last.id else {
            throw NSError(
                domain: "TripPlanning", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "所选出发日期不在当前预报范围（\(days.first?.id ?? "") 至 \(days.last?.id ?? "")）内。远期可查看周／月趋势，临近出发时再查询逐日天气。"
                ])
        }
        let selectedDays = Array(days.filter { $0.id >= start }.prefix(16))
        let atDeparture = try departureWeather(response, departure: departure, formatter: formatter)
        return WeatherForecast(current: atDeparture, days: selectedDays, elevation: response.elevation)
    }
    private static func requestForecast(at point: TrailPoint) async throws -> ForecastResponse {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(point.lat)),
            URLQueryItem(name: "longitude", value: String(point.lon)),
            URLQueryItem(name: "hourly", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(
                name: "daily",
                value:
                    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max"
            ),
            URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        return try JSONDecoder().decode(ForecastResponse.self, from: await TripHTTPClient.request(url.url!))
    }
    static func seasonalOutlook(at point: TrailPoint) async throws -> SeasonalOutlook {
        var url = URLComponents(string: "https://seasonal-api.open-meteo.com/v1/seasonal")!
        let variables =
            "temperature_2m_mean,temperature_2m_anomaly,precipitation_anomaly,wind_speed_10m_mean,cloud_cover_mean"
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(point.lat)),
            URLQueryItem(name: "longitude", value: String(point.lon)),
            URLQueryItem(name: "models", value: "ecmwf_seasonal_ensemble_mean_seamless"),
            URLQueryItem(name: "weekly", value: variables), URLQueryItem(name: "monthly", value: variables),
            URLQueryItem(name: "forecast_days", value: "210"), URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        return try decodeSeasonalOutlook(await TripHTTPClient.request(url.url!))
    }
    nonisolated static func decodeSeasonalOutlook(_ data: Data) throws -> SeasonalOutlook {
        let response = try JSONDecoder().decode(SeasonalResponse.self, from: data)
        let timezone =
            TimeZone(identifier: response.timezone) ?? TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        let weeks = try trends(response.weekly, monthly: false, formatter: formatter, calendar: calendar)
        let months = try trends(response.monthly, monthly: true, formatter: formatter, calendar: calendar)
        guard !weeks.isEmpty || !months.isEmpty else {
            throw NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: "远期趋势暂不可用。"])
        }
        return SeasonalOutlook(weeks: weeks, months: months, timezone: timezone)
    }
    nonisolated private static func failure(_ message: String) -> NSError {
        NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private struct ForecastResponse: Decodable {
        let elevation: Double?
        let timezone: String
        let utc_offset_seconds: Int
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let apparent_temperature: [Double?]
            let weather_code: [Int?]
        }
        let daily: Daily
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Double?]
            let precipitation_sum: [Double?]
            let wind_speed_10m_max: [Double?]
        }
    }
    nonisolated private static func forecastDays(_ response: ForecastResponse) throws -> [WeatherDay] {
        let day = response.daily
        let count = day.time.count
        guard
            [
                day.weather_code.count, day.temperature_2m_min.count, day.temperature_2m_max.count,
                day.precipitation_probability_max.count, day.precipitation_sum.count, day.wind_speed_10m_max.count,
            ].allSatisfy({ $0 == count }), count > 0
        else { throw failure("天气数据不完整，请重新查询。") }
        let days = (0..<count).compactMap { index -> WeatherDay? in
            guard let code = day.weather_code[index], let low = day.temperature_2m_min[index],
                let high = day.temperature_2m_max[index], let rainChance = day.precipitation_probability_max[index],
                let rain = day.precipitation_sum[index], let wind = day.wind_speed_10m_max[index],
                [low, high, rainChance, rain, wind].allSatisfy(\.isFinite)
            else { return nil }
            return WeatherDay(
                id: day.time[index], code: code, low: low, high: high,
                rainChance: rainChance, rain: rain, wind: wind)
        }
        guard !days.isEmpty else { throw failure("天气数据不完整，请重新查询。") }
        return days
    }

    nonisolated private static func departureWeather(
        _ response: ForecastResponse, departure: Date, formatter: DateFormatter
    ) throws
        -> WeatherNow
    {
        formatter.dateFormat = "yyyy-MM-dd'T'HH':00'"
        let hour = formatter.string(from: departure)
        let hourly = response.hourly
        guard let index = hourly.time.firstIndex(of: hour), hourly.temperature_2m.indices.contains(index),
            hourly.apparent_temperature.indices.contains(index), hourly.weather_code.indices.contains(index),
            let temperature = hourly.temperature_2m[index], let apparent = hourly.apparent_temperature[index],
            let code = hourly.weather_code[index]
        else {
            throw failure("出发时段的小时预报暂不可用，请调整出发时间或稍后查询。")
        }
        let atDeparture = WeatherNow(
            time: hour, temperature_2m: temperature, apparent_temperature: apparent, weather_code: code)
        return atDeparture
    }
    struct Periods: Decodable {
        let time: [String]
        let temperature_2m_mean: [Double?]
        let temperature_2m_anomaly: [Double?]
        let precipitation_anomaly: [Double?]
        let wind_speed_10m_mean: [Double?]?
        let cloud_cover_mean: [Double?]?
    }
    struct SeasonalResponse: Decodable {
        let timezone: String
        let utc_offset_seconds: Int
        let weekly: Periods
        let monthly: Periods
    }
    nonisolated private static func trends(
        _ periods: Periods, monthly: Bool, formatter: DateFormatter, calendar: Calendar
    ) throws -> [WeatherTrend] {
        let count = periods.time.count
        guard
            [
                periods.temperature_2m_mean.count, periods.temperature_2m_anomaly.count,
                periods.precipitation_anomaly.count,
            ].allSatisfy({ $0 == count })
        else {
            throw NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: "远期趋势数据不完整。"])
        }
        return (0..<count).compactMap { index in
            guard let temperature = periods.temperature_2m_mean[index],
                let anomaly = periods.temperature_2m_anomaly[index],
                let precipitation = periods.precipitation_anomaly[index],
                [temperature, anomaly, precipitation].allSatisfy(\.isFinite),
                let start = formatter.date(from: periods.time[index]),
                let next = calendar.date(byAdding: monthly ? .month : .day, value: monthly ? 1 : 7, to: start),
                let end = calendar.date(byAdding: .day, value: -1, to: next)
            else { return nil }
            return WeatherTrend(
                id: periods.time[index], end: formatter.string(from: end), monthly: monthly,
                temperature: temperature, temperatureAnomaly: anomaly, precipitationAnomaly: precipitation,
                wind: optionalValue(periods.wind_speed_10m_mean, at: index),
                cloudCover: optionalValue(periods.cloud_cover_mean, at: index))
        }
    }
    nonisolated private static func optionalValue(_ values: [Double?]?, at index: Int) -> Double? {
        guard let values, values.indices.contains(index), let value = values[index], value.isFinite else {
            return nil
        }
        return value
    }

}

import Foundation

struct TripWeather: Decodable {
    let daily: Daily

    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_probability_max: [Double?]?
        let wind_speed_10m_max: [Double?]
        let weather_code: [Int?]
    }

    var firstDay: Day? {
        guard let date = daily.time.first,
              let high = daily.temperature_2m_max.first ?? nil,
              let low = daily.temperature_2m_min.first ?? nil else { return nil }
        return Day(date: date, high: high, low: low,
                   precipitation: daily.precipitation_probability_max?.first ?? nil,
                   wind: daily.wind_speed_10m_max.first ?? nil,
                   code: daily.weather_code.first ?? nil)
    }

    var days: [Day] {
        daily.time.indices.compactMap { index in
            guard let high = daily.temperature_2m_max[index], let low = daily.temperature_2m_min[index] else { return nil }
            return Day(
                date: daily.time[index], high: high, low: low,
                precipitation: daily.precipitation_probability_max?[index] ?? nil,
                wind: daily.wind_speed_10m_max[index], code: daily.weather_code[index])
        }
    }

    func day(on date: Date) -> Day? {
        let key = date.formatted(.iso8601.year().month().day())
        return days.first { $0.date == key }
    }
}

struct Day {
    let date: String
    let high: Double
    let low: Double
    let precipitation: Double?
    let wind: Double?
    let code: Int?

    var condition: String {
        switch code ?? -1 {
        case 0: "晴"
        case 1, 2: "少云"
        case 3: "多云"
        case 45, 48: "雾"
        case 51...67: "小雨"
        case 71...77: "降雪"
        case 80...82: "阵雨"
        case 85, 86: "阵雪"
        case 95...99: "雷雨"
        default: "天气"
        }
    }

    var symbol: String {
        switch code ?? -1 {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        default: "cloud"
        }
    }
}

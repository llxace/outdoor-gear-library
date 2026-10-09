import Foundation

struct SeasonalOutlook {
    let weeks: [WeatherTrend]
    let months: [WeatherTrend]
    let timezone: TimeZone
    func trend(at departure: Date) -> WeatherTrend? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: departure)
        return (weeks + months).first { $0.id <= day && day <= $0.end }
    }
}

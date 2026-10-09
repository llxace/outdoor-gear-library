import Foundation

@main struct WeatherRegressionChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw NSError(domain: "WeatherChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        count += 1
    }
    static func main() throws {
        let fixture: [String: Any] = [
            "timezone": "Asia/Shanghai", "utc_offset_seconds": 28800, "elevation": 100,
            "hourly": ["time": ["2026-10-09T12:00"], "temperature_2m": [10], "apparent_temperature": [8], "weather_code": [0]],
            "daily": ["time": ["2026-10-09", "2026-10-10"], "weather_code": [0, NSNull()],
                "temperature_2m_max": [15, NSNull()], "temperature_2m_min": [5, NSNull()],
                "precipitation_probability_max": [10, 20], "precipitation_sum": [0, NSNull()], "wind_speed_10m_max": [5, NSNull()]]
        ]
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: "2026-10-09T12:00:00+08:00")!
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let result = try WeatherService.decodeForecast(data, departure: date)
        try expect(result.days.count == 1 && result.days[0].id == "2026-10-09", "skip incomplete day")
        try expect(result.current.temperature_2m == 10 && result.current.apparent_temperature == 8, "valid departure preserved")
        do {
            _ = try WeatherService.decodeForecast(data, departure: formatter.date(from: "2026-10-10T12:00:00+08:00")!)
            throw NSError(domain: "WeatherChecks", code: 1)
        } catch {
            try expect((error as NSError).domain == "TripPlanning" && (error as NSError).code == 2, "incomplete departure gets range error")
        }
        var invalid = fixture
        var daily = fixture["daily"] as! [String: Any]
        daily["temperature_2m_max"] = [NSNull(), NSNull()]; invalid["daily"] = daily
        var rejected = false
        do { _ = try WeatherService.decodeForecast(JSONSerialization.data(withJSONObject: invalid), departure: date) } catch { rejected = true }
        try expect(rejected, "all incomplete rejected")
        daily["temperature_2m_max"] = [15]; invalid["daily"] = daily; rejected = false
        do { _ = try WeatherService.decodeForecast(JSONSerialization.data(withJSONObject: invalid), departure: date) } catch { rejected = true }
        try expect(rejected, "mismatched arrays rejected")
        if CommandLine.arguments.count > 1 {
            let real = try WeatherService.decodeForecast(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), departure: date)
            try expect(!real.days.isEmpty && real.days.count < 16, "actual response with null final day")
        }
        print("PASS: \(count) assertions; partial weather, hourly values, unavailable departure, all-null and array mismatch safety")
    }
}

import SwiftUI
import MapKit
import Charts

enum WeatherCurve: String, CaseIterable, Identifiable {
    case temperature = "平均气温"
    case temperatureAnomaly = "气温较常年差值"
    case precipitation = "降水较常年差值"
    case wind = "平均风速"
    case cloud = "平均云量"
    var id: String { rawValue }
    var unit: String {
        switch self {
        case .temperature, .temperatureAnomaly: return "°C"
        case .precipitation: return "mm"
        case .wind: return "km/h"
        case .cloud: return "%"
        }
    }
    var color: Color {
        switch self {
        case .temperature: return .orange
        case .temperatureAnomaly: return .red
        case .precipitation: return .blue
        case .wind: return .mint
        case .cloud: return .purple
        }
    }
    func value(in trend: WeatherTrend) -> Double? {
        switch self {
        case .temperature: return trend.temperature
        case .temperatureAnomaly: return trend.temperatureAnomaly
        case .precipitation: return trend.precipitationAnomaly
        case .wind: return trend.wind
        case .cloud: return trend.cloudCover
        }
    }
}

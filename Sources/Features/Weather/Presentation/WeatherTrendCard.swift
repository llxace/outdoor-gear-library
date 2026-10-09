import SwiftUI
import MapKit
import Charts

struct WeatherTrendCard: View {
    let trend: WeatherTrend
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trend.period + (trend.monthly ? " · 月趋势" : " · 周趋势")).font(.headline)
            HStack(spacing: 18) {
                Label(
                    "均温 " + trend.temperature.formatted(.number.precision(.fractionLength(1))) + " °C",
                    systemImage: "thermometer.medium")
                Text(
                    "较常年 "
                        + trend.temperatureAnomaly.formatted(
                            .number.sign(strategy: .always()).precision(.fractionLength(1))) + " °C")
                Text(
                    "降水较常年 "
                        + trend.precipitationAnomaly.formatted(
                            .number.sign(strategy: .always()).precision(.fractionLength(1))) + " mm")
            }.font(.callout)
            HStack(spacing: 18) {
                if let wind = trend.wind {
                    Label(
                        "平均风速 " + wind.formatted(.number.precision(.fractionLength(1))) + " km/h", systemImage: "wind")
                }
                if let cloud = trend.cloudCover {
                    Label("平均云量 " + cloud.formatted(.number.precision(.fractionLength(0))) + "%", systemImage: "cloud")
                }
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

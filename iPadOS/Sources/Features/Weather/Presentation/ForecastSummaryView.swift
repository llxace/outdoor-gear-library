import SwiftUI

struct ForecastSummaryView: View {
    let forecast: WeatherForecast
    let compact: Bool
    let detailed: Bool
    let dayHeight: CGFloat
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                if !compact { Text("出发时段预报").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    Image(systemName: forecast.current.conditions.1).font(.system(size: detailed ? 34 : 24))
                        .symbolRenderingMode(.multicolor)
                    Text(forecast.current.temperature_2m.formatted(.number.precision(.fractionLength(0))) + "°").font(
                        .system(size: detailed ? 48 : 30, weight: .light))
                }
                Text(forecast.current.conditions.0).font(.headline)
                if !compact {
                    Text(
                        "体感 " + forecast.current.apparent_temperature.formatted(.number.precision(.fractionLength(0)))
                            + " °C"
                    ).font(.caption)
                }
                if detailed {
                    Text("当地 " + forecast.current.time.replacingOccurrences(of: "T", with: " ")).font(.caption)
                        .foregroundStyle(.secondary)
                }
                if detailed, let today = forecast.days.first {
                    Text("最高 \(today.high.formatted())° · 最低 \(today.low.formatted())°").font(.caption)
                }
            }.frame(width: detailed ? 160 : 125, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(forecast.days) { day in
                        VStack(spacing: detailed ? 8 : 3) {
                            Text(String(day.id.suffix(5))).font(.caption.bold())
                            Image(systemName: day.conditions.1).font(compact ? .body : .title2).symbolRenderingMode(
                                .multicolor)
                            if detailed { Text(day.conditions.0) }
                            Text(
                                "\(day.low.formatted(.number.precision(.fractionLength(0))))–\(day.high.formatted(.number.precision(.fractionLength(0))))°"
                            ).fontWeight(.medium)
                            if !compact {
                                Text("降水 \(day.rainChance.formatted(.number.precision(.fractionLength(0))))%")
                            }
                            if detailed { Text("风速 \(day.wind.formatted()) km/h") }
                        }.font(.caption).padding(detailed ? 10 : 4).frame(minWidth: 80, maxHeight: .infinity)
                            .background(GearDesign.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(height: dayHeight)
        }
    }
}

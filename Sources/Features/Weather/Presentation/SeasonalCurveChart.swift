import SwiftUI
import MapKit
import Charts

struct SeasonalCurveChart: View {
    let curves: [WeatherCurve]
    let trends: [WeatherTrend]
    let departureTrend: WeatherTrend?
    private var hasValues: Bool { trends.contains { trend in curves.contains { $0.value(in: trend) != nil } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(curves.map(\.rawValue).joined(separator: " / ")).font(.headline)
                Spacer()
                Text(curves.first?.unit ?? "").font(.caption).foregroundStyle(.secondary)
            }
            if hasValues {
                Chart {
                    ForEach(curves) { curve in
                        ForEach(trends) { trend in
                            if let value = curve.value(in: trend) {
                                LineMark(x: .value("时段", trend.period), y: .value(curve.unit, value))
                                    .foregroundStyle(by: .value("要素", curve.rawValue))
                                    .lineStyle(
                                        StrokeStyle(lineWidth: 2, dash: curve == .temperatureAnomaly ? [5, 4] : []))
                                PointMark(x: .value("时段", trend.period), y: .value(curve.unit, value))
                                    .foregroundStyle(by: .value("要素", curve.rawValue))
                                    .symbol(by: .value("要素", curve.rawValue)).symbolSize(28)
                                    .accessibilityLabel(trend.period + "，" + curve.rawValue)
                                    .accessibilityValue(
                                        value.formatted(.number.precision(.fractionLength(1))) + " " + curve.unit)
                            }
                        }
                    }
                    if let departureTrend, trends.contains(where: { $0.id == departureTrend.id }) {
                        RuleMark(x: .value("出发时段", departureTrend.period))
                            .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("出发" + (departureTrend.monthly ? "月" : "周")).font(.caption2).foregroundStyle(
                                    .secondary)
                            }
                    }
                }
                .chartForegroundStyleScale(domain: curves.map(\.rawValue), range: curves.map(\.color))
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)
            } else {
                Text("当前时段暂无此要素的数据。").foregroundStyle(.secondary)
            }
        }.padding(16).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

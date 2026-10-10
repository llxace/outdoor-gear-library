import SwiftUI
import MapKit
import Charts

struct SeasonalWeatherView: View {
    let outlook: SeasonalOutlook?
    let loading: Bool
    let error: String?
    let departure: Date
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("seasonalTemperatureCurve") private var temperature = true
    @AppStorage("seasonalTemperatureAnomalyCurve") private var temperatureAnomaly = false
    @AppStorage("seasonalPrecipitationCurve") private var precipitation = true
    @AppStorage("seasonalWindCurve") private var wind = false
    @AppStorage("seasonalCloudCurve") private var cloud = false
    @State private var monthly = false
    private var selectedCurves: [WeatherCurve] {
        WeatherCurve.allCases.filter { curve in
            switch curve {
            case .temperature: return temperature
            case .temperatureAnomaly: return temperatureAnomaly
            case .precipitation: return precipitation
            case .wind: return wind
            case .cloud: return cloud
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("远期天气趋势", systemImage: "chart.xyaxis.line").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("勾选想看的曲线。周／月均值用于远期规划；温差与降水差的正值表示较常年偏暖、偏湿。").foregroundStyle(.secondary)
            Picker("趋势范围", selection: $monthly) {
                Text("周趋势 · 约 6 周").tag(false)
                Text("月趋势 · 最多 7 个月").tag(true)
            }.pickerStyle(.segmented)
            HStack(spacing: 18) {
                Toggle("平均气温", isOn: $temperature)
                Toggle("气温差", isOn: $temperatureAnomaly)
                Toggle("降水差", isOn: $precipitation)
                Toggle("平均风速", isOn: $wind)
                Toggle("平均云量", isOn: $cloud)
            }.toggleStyle(.switch)
            if loading {
                ProgressView("正在查询远期趋势…")
            } else if let error {
                HStack {
                    Text(error)
                    Button("重试", action: retry)
                }
            } else if let outlook {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let trends = monthly ? outlook.months : outlook.weeks
                        let departureKey = dateKey(outlook.timezone)
                        let selected = trends.first { $0.id <= departureKey && departureKey <= $0.end }
                        if selectedCurves.isEmpty {
                            Text("勾选上方至少一种要素以显示曲线。").foregroundStyle(.secondary).frame(
                                maxWidth: .infinity, minHeight: 220)
                        } else {
                            ForEach(["°C", "mm", "km/h", "%"], id: \.self) { unit in
                                let curves = selectedCurves.filter { $0.unit == unit }
                                if !curves.isEmpty {
                                    SeasonalCurveChart(curves: curves, trends: trends, departureTrend: selected)
                                }
                            }
                        }
                        if selected == nil {
                            Text("本次出发日期不在当前图表范围，可切换周／月趋势查看。").font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("查看具体数值") { ForEach(trends) { WeatherTrendCard(trend: $0) } }
                    }
                }
            }
            Text(
                "ECMWF EC46 / SEAS5 集合平均 · 约 36 km 区域网格，未作偏差订正。均温不代表最低温，平均风速不代表阵风；云量不是降雨概率。远期趋势不能判断某天晴雨或山顶天气，临近出发请复查逐日预报。"
            ).font(.caption).foregroundStyle(.secondary)
            Link(
                "数据来源与说明 · Open-Meteo / ECMWF",
                destination: URL(string: "https://open-meteo.com/en/docs/seasonal-forecast-api")!
            ).font(.caption)
        }.padding(24).frame(maxWidth: 1000, maxHeight: .infinity)
            .onAppear { monthly = outlook?.trend(at: departure)?.monthly ?? false }
    }
    private func dateKey(_ timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: departure)
    }
}

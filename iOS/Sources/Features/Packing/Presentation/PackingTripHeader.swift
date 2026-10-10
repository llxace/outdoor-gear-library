import SwiftUI
import MapKit
import Charts

struct PackingTripHeader: View {
    let availableHeight: CGFloat
    let availableWidth: CGFloat
    private var compact: Bool { availableHeight < 200 }
    private var detailed: Bool { availableHeight >= 300 || (showWeatherDetails && availableHeight >= 240) }
    private var dayHeight: CGFloat { compact ? 55 : max(detailed ? 146 : 80, availableHeight - (detailed ? 150 : 110)) }
    @EnvironmentObject var store: GearStore
    @StateObject private var model = TripConditionsModel()
    @State private var choosingRoute = false
    @State private var expandedMap = false
    @State private var choosingDeparture = false
    @State private var departureDraft = Date()
    @State private var showWeatherDetails = false
    @State private var showingOutlook = false
    @State private var refresh = UUID()
    private var route: HikingRoute? { store.inventory.selectedRoute }
    private var earliestSelectableDeparture: Date {
        DepartureCalendar.earliestSelectableDate(from: Date())
    }

    private func prepareDepartureDraft() {
        departureDraft = max(store.inventory.mealPlan.startDate, earliestSelectableDeparture)
    }

    private func canSelectDepartureTime(hour: Int, minute: Int) -> Bool {
        guard let candidate = Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: departureDraft
        ) else { return false }
        return candidate >= earliestSelectableDeparture
    }

    private func departureComponent(_ component: Calendar.Component) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(component, from: departureDraft) },
            set: { value in
                let hour = component == .hour ? value : Calendar.current.component(.hour, from: departureDraft)
                let minute = component == .minute ? value : Calendar.current.component(.minute, from: departureDraft)
                if let date = Calendar.current.date(
                    bySettingHour: hour, minute: minute, second: 0, of: departureDraft
                ), date >= earliestSelectableDeparture {
                    departureDraft = date
                }
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            routeHeading
            Divider()
            HStack(alignment: .top, spacing: 12) {
                weatherContent
                if let route {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("路线图", systemImage: "map").font(.headline)
                            Spacer()
                            Button("放大", systemImage: "arrow.up.left.and.arrow.down.right") { expandedMap = true }
                        }
                        RouteMap(route: route, mapType: .standard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                Button {
                                    expandedMap = true
                                } label: {
                                    Color.clear.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).accessibilityLabel("放大" + route.name + "路线图").help("点击打开大地图")
                            }
                        RouteMetricSummary(
                            route: route, terrain: model.terrain, error: model.terrainError, compact: true)
                        if route.segments.isEmpty {
                            Text("仅显示目的地位置，暂无路线轨迹").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(width: min(450, max(240, availableWidth * 0.32)), height: max(95, availableHeight - 55))
                }
            }
        }.padding(10).frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .topLeading).background(
            LinearGradient(
                colors: [GearDesign.accent.opacity(0.18), GearDesign.surface], startPoint: .topLeading,
                endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .sheet(isPresented: $showingOutlook) {
            SeasonalWeatherView(
                outlook: model.outlook, loading: model.outlookLoading, error: model.outlookError,
                departure: store.inventory.mealPlan.startDate, retry: { refresh = UUID() })
        }
        .sheet(isPresented: $choosingRoute) { RouteSearchView().environmentObject(store) }
        .sheet(isPresented: $expandedMap) {
            if let route { ExpandedRouteMap(route: route, terrain: model.terrain, error: model.terrainError) }
        }
        .task(id: route) { await model.loadTerrain(route: route) }
        .task(
            id:
                "\(route?.id ?? 0)-\(route?.distance ?? "")-\(route?.center.lat ?? 0)-\(route?.center.lon ?? 0)-\(store.inventory.mealPlan.startDate.timeIntervalSince1970)-\(refresh)"
        ) { await model.loadForecast(route: route, departure: store.inventory.mealPlan.startDate) }
        .task(id: "seasonal-\(route?.id ?? 0)-\(refresh)") { await model.loadOutlook(route: route) }
    }

    private var departureEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择出发时间").font(.title3.weight(.semibold))
                Text("仅可选择今天及之后的日期和时间")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DepartureCalendar(selection: $departureDraft)
            Divider()
            HStack {
                Label("出发时刻", systemImage: "clock").foregroundStyle(.secondary)
                Spacer()
                Picker("小时", selection: departureComponent(.hour)) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                            .disabled(!canSelectDepartureTime(
                                hour: hour, minute: Calendar.current.component(.minute, from: departureDraft)))
                    }
                }.labelsHidden().frame(width: 68)
                Text(":").foregroundStyle(.secondary)
                Picker("分钟", selection: departureComponent(.minute)) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                            .disabled(!canSelectDepartureTime(
                                hour: Calendar.current.component(.hour, from: departureDraft), minute: minute))
                    }
                }.labelsHidden().frame(width: 68)
            }
            HStack {
                Button("取消") { choosingDeparture = false }
                Spacer()
                Button("确认") {
                    var plan = store.inventory.mealPlan
                    plan.startDate = max(departureDraft, earliestSelectableDeparture)
                    if store.saveMealPlan(plan) { choosingDeparture = false }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 340)
    }

    private var weatherHeading: some View {
        HStack {
            Label(
                model.departureHasPassed
                    ? "天气预报 · 出发时间已过"
                    : model.outsideForecastRange
                    ? "远期天气趋势 · 按出发日期" : "天气预报 · 出发日起" + (model.forecast.map { " \($0.days.count) 天" } ?? "最多 16 天"),
                systemImage: "cloud.sun"
            ).font(.headline)
            Spacer()
            if let updated = model.updated {
                Text("更新于 " + updated.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(
                    .secondary)
            }
            if route != nil {
                Button("远期趋势") { showingOutlook = true }
                    .font(.caption).disabled(model.departureHasPassed)
                    .help(model.departureHasPassed ? "所选出发时间已过去，请先调整出发时间" : "查看周／月天气趋势")
            }
            if model.forecast != nil {
                Button(showWeatherDetails ? "收起详情" : "详细天气") { showWeatherDetails.toggle() }.font(.caption)
            }
            if route != nil {
                Button {
                    refresh = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("刷新天气").disabled(model.loading)
            }
        }
    }

    private var routeHeading: some View {
        HStack(spacing: 12) {
            Label(route?.destinationOnly == true ? "本次目的地" : "本次路线", systemImage: "map").font(.headline)
            if let route {
                Text(route.name).font(.headline).lineLimit(1)
                if !route.distance.isEmpty { Text(route.distance).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("选择路线后，对照天气整理装备").foregroundStyle(.secondary)
            }
            Button {
                prepareDepartureDraft()
                choosingDeparture = true
            } label: {
                Label(
                    "出发 " + store.inventory.mealPlan.startDate.formatted(.dateTime.month().day().hour().minute()),
                    systemImage: "calendar")
            }.popover(isPresented: $choosingDeparture, arrowEdge: .bottom) {
                departureEditor
            }.help("点击日历选择日期；按当前系统时区填写，路餐日期同步更新。")
            Spacer()
            Button(
                route == nil ? "在线选择路线" : (route?.destinationOnly == true ? "更换目的地" : "更换路线"),
                systemImage: "magnifyingglass"
            ) { choosingRoute = true }.buttonStyle(.bordered)
            if let route {
                Menu {
                    Link("查看路线资料", destination: route.sourceURL)
                    Button("移除路线") { _ = store.selectRoute(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).fixedSize().help("路线资料与移除")
            }
        }
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            weatherHeading
            if route == nil {
                Text("选好路线后，这里会显示路线中心附近的气温、降水和风速。").font(.callout).foregroundStyle(.secondary)
            } else if model.loading {
                ProgressView("正在查询路线附近的天气…").controlSize(.small)
            } else if model.departureHasPassed {
                Label("所选出发时间已过去，无法显示天气预报。", systemImage: "clock.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
                Button("调整出发时间") {
                    prepareDepartureDraft()
                    choosingDeparture = true
                }.font(.caption)
            } else if model.outsideForecastRange,
                let trend = model.outlook?.trend(at: store.inventory.mealPlan.startDate)
            {
                WeatherTrendCard(trend: trend)
                Text("所选日期超出逐日预报范围，显示对应" + (trend.monthly ? "月" : "周") + "的区域趋势；不是出发当天的天气。").font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = model.error {
                HStack {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button("重试") { refresh = UUID() }
                }
                if model.outsideForecastRange && model.outlookLoading { ProgressView("正在查询远期趋势…").controlSize(.small) }
            } else {
                if let forecast = model.forecast {
                    ForecastSummaryView(forecast: forecast, compact: compact, detailed: detailed, dayHeight: dayHeight)
                }
                if !compact {
                    HStack {
                        Text(
                            (route?.destinationOnly == true ? "目的地附近" : "路线中心附近")
                                + (model.forecast?.elevation.map {
                                    " · 网格海拔约 " + $0.formatted(.number.precision(.fractionLength(0))) + " 米"
                                } ?? "")
                        )
                        .foregroundStyle(.secondary)
                        Spacer()
                        Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                    }.font(.caption)
                }
                if detailed {
                    Text("小时预报取出发时刻所在整点，日期按目的地当地时间；显示当前可用的出发日起最多 16 天，超出预报范围的部分不可用。不同海拔、路段的天气可能不同。").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

import MapKit
import SwiftUI

struct RouteWeatherCard: View {
    @EnvironmentObject private var library: GearLibrary
    @StateObject private var weather = TripWeatherModel()
    @State private var choosingRoute = false
    @State private var importingTrack = false
    @State private var departure = Date()

    private var route: RouteSnapshot? { library.selectedRouteSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("本次路线", systemImage: "map.fill").font(.headline)
                Spacer()
                Menu {
                    Button("从路线目录选择", systemImage: "magnifyingglass") { choosingRoute = true }
                    Button("导入 GPX / KML 轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up") { importingTrack = true }
                    if route != nil {
                        Button("清除本次路线", systemImage: "xmark", role: .destructive) { library.selectRoute(nil) }
                    }
                } label: {
                    Label(route == nil ? "选择路线" : "更换路线", systemImage: "map.badge.ellipse")
                }.buttonStyle(.bordered)
            }
            if let route {
                Text(route.name).font(.title3.bold())
                HStack {
                    Label(route.area, systemImage: "mappin.and.ellipse")
                    Spacer()
                    Text(route.distance).foregroundStyle(OutdoorPalette.warm)
                }.font(.subheadline).foregroundStyle(.secondary)
                RouteMapCard(route: route)
                HStack {
                    Label("出发", systemImage: "calendar")
                    DatePicker("", selection: $departure, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .onChange(of: departure) { _, newValue in
                            library.updateDepartureDate(newValue)
                        }
                }
                weatherSummary
            } else {
                ContentUnavailableView("还没有选择路线", systemImage: "map", description: Text("选好路线后可查看地图和出发日天气。"))
            }
        }
        .modifier(DataCardStyle())
        .sheet(isPresented: $choosingRoute) { RoutePickerView().environmentObject(library) }
        .fileImporter(isPresented: $importingTrack, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { library.importTrackFile(url) }
            case .failure(let error): library.alert = "无法打开轨迹文件：\(error.localizedDescription)"
            }
        }
        .onAppear { departure = max(library.departureDate, Date.now) }
        .task(id: "\(route?.id ?? 0)-\(departure.timeIntervalSince1970)") {
            await weather.load(route: route, date: departure)
        }
    }

    @ViewBuilder private var weatherSummary: some View {
        if weather.isLoading {
            HStack { ProgressView(); Text("正在获取出发地天气…").foregroundStyle(.secondary) }.font(.subheadline)
        } else if let day = weather.day {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: day.symbol).font(.title2).foregroundStyle(OutdoorPalette.warm)
                    Text(day.condition).font(.headline)
                    Text("\(Int(day.low.rounded()))°–\(Int(day.high.rounded()))°")
                    Spacer(minLength: 2)
                    if let probability = day.precipitation { Label("\(Int(probability.rounded()))%", systemImage: "drop") }
                    if let wind = day.wind { Label("\(Int(wind.rounded())) km/h", systemImage: "wind") }
                }.font(.caption)
                if !weather.days.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(weather.days.enumerated()), id: \.offset) { _, forecast in
                                VStack(spacing: 5) {
                                    Text(String(forecast.date.suffix(5))).font(.caption2).foregroundStyle(.secondary)
                                    Image(systemName: forecast.symbol).foregroundStyle(OutdoorPalette.warm)
                                    Text("\(Int(forecast.high.rounded()))°").font(.caption.bold())
                                    Text("\(Int(forecast.low.rounded()))°").font(.caption2).foregroundStyle(.secondary)
                                    if let rain = forecast.precipitation {
                                        Text("\(Int(rain.rounded()))%").font(.caption2).foregroundStyle(rain >= 40 ? OutdoorPalette.accent : .secondary)
                                    }
                                }
                                .frame(width: 62)
                                .padding(.vertical, 8)
                                .background(forecast.date == day.date ? OutdoorPalette.glassTint : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                Text("路线附近的每日预报 · Open-Meteo · 最多 16 天").font(.caption2).foregroundStyle(.tertiary)
            }
        } else if let message = weather.message {
            Label(message, systemImage: "cloud.sun").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct RouteMapCard: View {
    let route: RouteSnapshot
    @State private var position: MapCameraPosition

    init(route: RouteSnapshot) {
        self.route = route
        let center = CLLocationCoordinate2D(latitude: route.center.lat, longitude: route.center.lon)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20))))
    }

    var body: some View {
        Map(position: $position) {
            ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map(\.coordinate)).stroke(Color.cyan, lineWidth: 4)
                }
            }
            Marker(route.name, coordinate: CLLocationCoordinate2D(latitude: route.center.lat, longitude: route.center.lon))
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 210)
        .id(route.id)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            if route.segments.isEmpty {
                Text("路线目录提供目的地位置；轨迹暂未加载")
                    .font(.caption2).padding(7).background(.regularMaterial, in: Capsule()).padding(8)
            }
        }
    }
}

import SwiftUI
import MapKit
import Charts

struct ExpandedRouteMap: View {
    let route: HikingRoute
    let terrain: RouteTerrain?
    let error: String?
    @Environment(\.dismiss) private var dismiss
    @State private var mapType = MKMapType.standard
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(route.name).font(.title2.bold())
                Spacer()
                Picker("地图", selection: $mapType) {
                    Text("标准").tag(MKMapType.standard)
                    Text("卫星").tag(MKMapType.hybrid)
                }.pickerStyle(.segmented).frame(width: 150)
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 16) {
                RouteMap(route: route, mapType: mapType).clipShape(RoundedRectangle(cornerRadius: 10))
                ScrollView { RouteMetricSummary(route: route, terrain: terrain, error: error) }.frame(width: 250)
            }
        }.padding(20).frame(minWidth: 850, idealWidth: 1000, minHeight: 550, idealHeight: 650)
    }
}

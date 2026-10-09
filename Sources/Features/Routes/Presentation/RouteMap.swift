import SwiftUI
import MapKit
import Charts

enum RouteMapLoadState: Equatable {
    case loading, ready, failed(String)
}

struct RouteMap: View {
    let route: HikingRoute
    let mapType: MKMapType
    @State private var reload = UUID()
    @State private var fitRevision = 0
    @State private var loadState = RouteMapLoadState.loading
    var body: some View {
        NativeRouteMap(route: route, mapType: mapType, fitRevision: fitRevision, loadChanged: { loadState = $0 })
            .id("\(route.id)-\(reload)")
            .overlay(alignment: .topLeading) { loadingStatus }
            .overlay(alignment: .bottomLeading) {
                if route.segments.allSatisfy({ $0.count < 2 }) {
                    Text("无轨迹点，仅显示地点").font(.caption).padding(8)
                        .background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.leading, 12).padding(.bottom, 30)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Button {
                        fitRevision += 1
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("显示整条路线").accessibilityLabel("显示整条路线")
                    Button {
                        loadState = .loading
                        reload = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("地图空白时重新加载底图和轨迹").accessibilityLabel("重载地图")
                }.buttonStyle(.borderless).padding(8).background(
                    GearDesign.surface, in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                ).padding(8)
            }
    }

    @ViewBuilder private var loadingStatus: some View {
        switch loadState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("地图加载中…").font(.caption)
            }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8)).padding(8)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("底图加载失败，轨迹仍可查看", systemImage: "exclamationmark.circle").font(.caption)
                Button("重试") { loadState = .loading; reload = UUID() }
            }.padding(10).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 8)).padding(8).help(message)
        case .ready: EmptyView()
        }
    }
}

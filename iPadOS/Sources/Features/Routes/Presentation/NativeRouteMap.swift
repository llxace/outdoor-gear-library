import SwiftUI
import MapKit
import Charts

struct NativeRouteMap: UIViewRepresentable {
    let route: HikingRoute
    let mapType: MKMapType
    let fitRevision: Int
    var loadChanged: (RouteMapLoadState) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> FittedRouteMap {
        let map = FittedRouteMap(frame: .zero)
        context.coordinator.loadChanged = loadChanged
        map.delegate = context.coordinator
        map.showsScale = true
        map.showsCompass = true

        return map
    }
    func updateUIView(_ map: FittedRouteMap, context: Context) {
        if map.mapType != mapType { map.mapType = mapType }
        let coordinator = context.coordinator
        coordinator.loadChanged = loadChanged
        // A route can receive its track after the summary, keeping the same identifier.
        if coordinator.route != route {
            coordinator.route = route
            replaceRoute(on: map)
            map.fitRouteOnNextLayout()
        }
        if coordinator.fitRevision != fitRevision {
            coordinator.fitRevision = fitRevision
            map.fitRouteOnNextLayout()
        }
    }
    private func replaceRoute(on map: FittedRouteMap) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        let lines = route.segments.filter { $0.count >= 2 && $0.allSatisfy(\.isValid) }.map { segment in
            MKPolyline(
                coordinates: segment.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                count: segment.count)
        }
        if !lines.isEmpty {
            map.addOverlays(lines)
            var rect = lines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            rect = rect.insetBy(
                dx: -max(0, (1000 - rect.size.width) / 2), dy: -max(0, (1000 - rect.size.height) / 2))
            map.routeRect = rect
        } else {
            let center = CLLocationCoordinate2D(latitude: route.center.lat, longitude: route.center.lon)
            let pin = MKPointAnnotation()
            pin.coordinate = center
            pin.title = route.name
            map.addAnnotation(pin)
            let region = MKCoordinateRegion(center: center, latitudinalMeters: 10000, longitudinalMeters: 10000)
            map.setRegion(region, animated: false)
            map.routeRect = map.visibleMapRect
        }
    }
    static func dismantleUIView(_ map: FittedRouteMap, coordinator: Coordinator) {
        map.delegate = nil
        coordinator.loadChanged = { _ in }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var route: HikingRoute?
        var fitRevision = 0
        var loadChanged: (RouteMapLoadState) -> Void = { _ in }
        func mapViewWillStartLoadingMap(_ mapView: MKMapView) { publish(.loading) }
        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {}
        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            publish(.failed(error.localizedDescription))
        }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered { publish(.ready) }
        }
        private func publish(_ state: RouteMapLoadState) {
            DispatchQueue.main.async { [weak self] in self?.loadChanged(state) }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 3
            return renderer
        }
    }
}

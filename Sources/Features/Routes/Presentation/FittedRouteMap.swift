import MapKit

final class FittedRouteMap: MKMapView {
    var routeRect: MKMapRect?
    private var fittedSize = NSSize.zero
    func fitRouteOnNextLayout() {
        fittedSize = .zero
        needsLayout = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { fitRouteOnNextLayout() }
    }
    override func layout() {
        super.layout()
        guard window != nil, bounds.width > 0, bounds.height > 0, bounds.size != fittedSize, let routeRect,
            !routeRect.isNull, !routeRect.isEmpty
        else { return }
        fittedSize = bounds.size
        setVisibleMapRect(
            routeRect, edgePadding: NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32), animated: false)
    }
}

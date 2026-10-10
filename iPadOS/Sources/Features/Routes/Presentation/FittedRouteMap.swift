import MapKit

final class FittedRouteMap: MKMapView {
    var routeRect: MKMapRect?
    private var fittedSize = CGSize.zero
    func fitRouteOnNextLayout() { fittedSize = .zero; setNeedsLayout() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { fitRouteOnNextLayout() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, bounds.width > 0, bounds.height > 0, bounds.size != fittedSize, let routeRect, !routeRect.isNull, !routeRect.isEmpty else { return }
        fittedSize = bounds.size
        setVisibleMapRect(routeRect, edgePadding: UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32), animated: false)
    }
}

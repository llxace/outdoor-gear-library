import SwiftUI
import UIKit

struct SockSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.42, 0.08))
        path.addLine(to: p(0.82, 0.08))
        path.addLine(to: p(0.82, 0.64))
        path.addQuadCurve(to: p(0.7, 0.83), control: p(0.82, 0.77))
        path.addLine(to: p(0.3, 0.97))
        path.addQuadCurve(to: p(0.1, 0.77), control: p(0.02, 0.94))
        path.addLine(to: p(0.42, 0.56))
        path.closeSubpath()
        path.addRect(
            CGRect(x: p(0.46, 0.2).x, y: p(0.46, 0.2).y, width: rect.width * 0.32, height: rect.height * 0.055))
        return path
    }
}

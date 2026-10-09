import SwiftUI
import AppKit

// 输出正方形 PNG，圆形遮罩只用于界面预览。
enum AvatarCropRenderer {
    static func png(image: NSImage, zoom: Double, offset: CGSize, viewport: CGFloat = 320) -> Data? {
        guard image.size.width > 0, image.size.height > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        let scale = max(viewport / image.size.width, viewport / image.size.height) * max(1, zoom) * 512 / viewport
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(
                x: (512 - size.width) / 2 + offset.width * 512 / viewport,
                y: (512 - size.height) / 2 - offset.height * 512 / viewport,
                width: size.width, height: size.height), from: NSRect(origin: .zero, size: image.size),
            operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

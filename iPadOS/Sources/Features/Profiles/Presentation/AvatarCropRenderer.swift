import SwiftUI
import UIKit

enum AvatarCropRenderer {
    static func png(image: UIImage, zoom: Double, offset: CGSize, viewport: CGFloat = 320) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let output = renderer.image { _ in
            let scale = max(viewport / image.size.width, viewport / image.size.height) * max(1, zoom) * 512 / viewport
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: (512 - size.width) / 2 + offset.width * 512 / viewport, y: (512 - size.height) / 2 - offset.height * 512 / viewport, width: size.width, height: size.height)
            image.draw(in: rect)
        }
        return output.pngData()
    }
}

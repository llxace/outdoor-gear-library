import Foundation
import UIKit
import Vision
import CoreImage

/// 在设备本地将产品照片裁成方形；可选用 Vision 做主体抠图并加白底和阴影。
enum ProductPhotoProcessor {
    static func process(source: URL, destination: URL, white: Bool, shadow: Bool) throws {
        guard let input = UIImage(contentsOfFile: source.path), let cgImage = input.cgImage else {
            throw failure("无法读取这张照片，请换一张图片。")
        }
        let normalized = UIGraphicsImageRenderer(size: input.size).image { _ in input.draw(in: CGRect(origin: .zero, size: input.size)) }
        let square = centerSquare(normalized)
        let result: UIImage
        if white {
            let request = VNGenerateForegroundInstanceMaskRequest()
            do {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try handler.perform([request])
                guard let observation = request.results?.first else { throw failure("未能识别照片主体，请换一张主体清楚的照片。") }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
                let ci = CIImage(cvPixelBuffer: buffer)
                let context = CIContext()
                guard let masked = context.createCGImage(ci, from: ci.extent) else { throw failure("抠图生成失败，请重试。") }
                let foreground = centerSquare(UIImage(cgImage: masked))
                result = render(foreground: foreground, white: true, shadow: shadow)
            } catch { throw failure("照片主体处理失败：\\(error.localizedDescription)") }
        } else {
            result = render(foreground: square, white: false, shadow: false)
        }
        guard let data = result.pngData() else { throw failure("无法保存处理后的照片。") }
        try data.write(to: destination, options: .atomic)
    }

    private static func centerSquare(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024)).image { _ in
            image.draw(in: CGRect(x: -origin.x * 1024 / side, y: -origin.y * 1024 / side,
                                 width: image.size.width * 1024 / side, height: image.size.height * 1024 / side))
        }
    }

    private static func render(foreground: UIImage, white: Bool, shadow: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024)).image { context in
            if white { UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
            let inset: CGFloat = white ? 70 : 0
            let rect = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
            if white && shadow {
                context.cgContext.saveGState()
                context.cgContext.setShadow(offset: CGSize(width: 0, height: 16), blur: 28, color: UIColor.black.withAlphaComponent(0.22).cgColor)
                foreground.draw(in: rect)
                context.cgContext.restoreGState()
            }
            foreground.draw(in: rect)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ProductPhoto", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

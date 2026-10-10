import SwiftUI
import UIKit
import AVFoundation

struct FoodCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var video: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        init(session: AVCaptureSession) { super.init(frame: .zero); video.session = session; video.videoGravity = .resizeAspect }
        required init?(coder: NSCoder) { fatalError() }
    }
    func makeUIView(context: Context) -> Preview { Preview(session: session) }
    func updateUIView(_ view: Preview, context: Context) {}
}

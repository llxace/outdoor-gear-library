import SwiftUI
import AppKit
import Vision
import AVFoundation
import UniformTypeIdentifiers

struct FoodCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        let video: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            video = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            video.videoGravity = .resizeAspect
            layer?.addSublayer(video)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            video.frame = bounds
        }
    }
    func makeNSView(context: Context) -> Preview { Preview(session: session) }
    func updateNSView(_ view: Preview, context: Context) {}
}

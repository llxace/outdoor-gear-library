import Foundation
import Combine
import AVFoundation

final class FoodCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "OutdoorGear.food-camera")
    private let lock = NSLock()
    private var active = false
    @Published var ready = false
    @Published var failure: String?
    @Published var photo: Data?
    @Published var capturing = false
    func start() {
        lock.lock()
        active = true
        lock.unlock()
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else {
                DispatchQueue.main.async { self.failure = "摄像头未获授权。可改用选择包装照片。" }
                return
            }
            self.queue.async {
                self.configureSession()
            }
        }
    }
    // Called only on the camera queue, including after authorization completes.
    private func configureSession() {
        self.lock.lock()
        let active = self.active
        self.lock.unlock()
        guard active else { return }
        do {
            guard let device = AVCaptureDevice.default(for: .video) else {
                throw NSError(
                    domain: "FoodCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "未检测到摄像头，可选择手机拍好的照片。"])
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                throw NSError(
                    domain: "FoodCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "摄像头不支持拍照，请改用包装照片。"])
            }
            self.session.beginConfiguration()
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.ready = true }
        } catch { DispatchQueue.main.async { self.failure = error.localizedDescription } }
    }
    func stop() {
        lock.lock()
        active = false
        lock.unlock()
        queue.async { self.session.stopRunning() }
    }
    func capture() {
        guard ready, !capturing else { return }
        capturing = true
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async {
            self.capturing = false
            if let error {
                self.failure = error.localizedDescription
            } else if let data = photo.fileDataRepresentation() {
                self.photo = data
            } else {
                self.failure = "没有取得照片，请重试。"
            }
        }
    }
}

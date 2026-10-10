import SwiftUI
import UIKit
import Vision
import AVFoundation
import UniformTypeIdentifiers

struct FoodCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = FoodCamera()
    let use: (Data) -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("对准食品包装与营养表").font(.headline)
            FoodCameraPreview(session: camera.session).frame(width: 600, height: 360)
            if let failure = camera.failure { Text(failure).foregroundStyle(.secondary) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("拍照") { camera.capture() }.disabled(!camera.ready || camera.capturing)
            }
        }.padding(20).onAppear { camera.start() }.onDisappear { camera.stop() }
            .onChange(of: camera.photo) { _, photo in if let photo { use(photo) } }
    }
}

import SwiftUI
import UIKit
import Vision
import AVFoundation
import UniformTypeIdentifiers

struct FoodLabelScanner: View {
    @Environment(\.dismiss) private var dismiss
    let use: (FoodLabelResult) -> Void
    @State private var imageData: Data?
    @State private var text = ""
    @State private var scanning = false
    @State private var failure: String?
    @State private var camera = false
    private var result: FoodLabelResult { FoodLabelResult.parse(text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("识别食品包装").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }
            HStack {
                Button("摄像头拍照", systemImage: "camera") { camera = true }
                Button("选择包装照片…", systemImage: "photo") {
                    PadFileDialog.pick([.image]) { result in
                        do { guard let url = try result.get().first else { return }; imageData = try LocalAssetFiles.imageData(at: url); failure = nil }
                        catch { failure = error.localizedDescription }
                    }
                }
                Text("也可选择手机拍好的照片。本机识别，照片不会上传。").font(.caption).foregroundStyle(.secondary)
            }.disabled(scanning)
            GeometryReader { area in
                if area.size.width < 680 {
                    VStack(spacing: 8) {
                        labelImage.frame(height: area.size.height * 0.35)
                        recognitionText
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        labelImage.frame(width: min(280, area.size.width * 0.38))
                        recognitionText
                    }
                }
            }
            if scanning { ProgressView("正在识别包装文字…") }
            if let failure { Text(failure).foregroundStyle(.secondary) }
            HStack {
                Text("识别结果只填入草稿；请核对标签和份量后保存。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("填入食物草稿") { use(result) }.disabled(
                    scanning || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(maxWidth: 1000, maxHeight: .infinity)
            .sheet(isPresented: $camera) {
                FoodCameraView { data in
                    imageData = data
                    camera = false
                }
            }
            .task(id: imageData) {
                guard let imageData else { return }
                scanning = true
                failure = nil
                do {
                    let recognized = try await FoodTextRecognizer.recognize(imageData)
                    try Task.checkCancellation()
                    text = recognized
                    scanning = false
                } catch {
                    if !Task.isCancelled {
                        failure = error.localizedDescription
                        scanning = false
                    }
                }
            }
    }
    private var labelImage: some View {
        Group {
            if let data = imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Text("拍摄品名、净含量和营养表\n若不在包装同一面，可分别拍摄后在文字中合并")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }
    private var recognitionText: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("识别文字（可修正）").font(.headline)
            TextEditor(text: $text).frame(minHeight: 180)
            Text("品名：" + (result.name.isEmpty ? "待填写" : result.name))
            Text("净含量：" + (result.grams.map { $0.formatted() + " g" } ?? "未识别"))
            Text("每份热量：" + (result.calories.map { $0.formatted(.number.precision(.fractionLength(1))) + " kcal" } ?? "待确认"))
            Text(result.message).font(.caption).foregroundStyle(.secondary)
        }.padding(8)
    }
}

import SwiftUI
import AppKit

struct ProductPhotoEditor: View {
    @Environment(\.dismiss) private var dismiss
    let root: URL
    let source: String
    let apply: (String) -> Void
    @State private var white = false
    @State private var shadow = true
    @State private var busy = false
    @State private var preview: NSImage?
    @State private var original: NSImage?
    @State private var result: String?
    @State private var message = ""
    @State private var renderedWhite = false
    @State private var renderedShadow = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("整理装备照片").font(.title2.bold())
            Text("1024 × 1024 · PNG · 居中 · 物品最长边 82%").foregroundStyle(.secondary)
            HStack(spacing: 16) {
                photo(original, title: "原图")
                photo(preview, title: "处理后")
            }
            Toggle("抠图并换成白底", isOn: $white).disabled(busy)
            Toggle("添加柔和阴影", isOn: $shadow).disabled(busy || !white)
            Text("仅统一尺寸时保留原有背景与光影；白底处理保留物品颜色和纹理。")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView("正在本机处理…").accessibilityLabel("照片处理中") }
            if !message.isEmpty { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            photoActions
        }.padding(24).frame(width: 680)
            .interactiveDismissDisabled(busy)
            .task { render() }
    }
    private func photo(_ image: NSImage?, title: String) -> some View {
        VStack {
            Text(title).font(.headline)
            ZStack {
                Color.white
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(4)
                } else {
                    Image(systemName: "photo").foregroundStyle(.gray)
                }
            }.frame(width: 300, height: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(title)
        }
    }
    private func render() {
        guard !busy else { return }
        busy = true
        message = ""
        result = nil
        let filename = UUID().uuidString + ".png"
        let sourceURL = root.appendingPathComponent(source)
        let output = root.appendingPathComponent(filename)
        let useWhite = white
        let useShadow = shadow
        Task {
            do {
                let images = try await Task.detached(priority: .userInitiated) {
                    try ProductPhotoProcessor.process(
                        source: sourceURL, destination: output, white: useWhite, shadow: useShadow)
                    return (try LocalAssetFiles.imageData(at: sourceURL), try LocalAssetFiles.imageData(at: output))
                }.value
                original = NSImage(data: images.0)
                preview = NSImage(data: images.1)
                result = filename
                renderedWhite = useWhite
                renderedShadow = useShadow
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    private var photoActions: some View {
        HStack {
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            Spacer()
            Button("预览效果") { render() }.disabled(busy)
            Button("使用这张照片") {
                if let result {
                    apply(result)
                    dismiss()
                }
            }.keyboardShortcut(.defaultAction)
                .disabled(busy || result == nil || white != renderedWhite || (white && shadow != renderedShadow))
        }
    }
}

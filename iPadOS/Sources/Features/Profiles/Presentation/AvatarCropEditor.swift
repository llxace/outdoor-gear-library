import SwiftUI
import UIKit

struct AvatarCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let save: (URL) -> Void
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var failure: String?
    private var scale: CGFloat { max(320 / image.size.width, 320 / image.size.height) * zoom }
    private func capped(_ value: CGSize) -> CGSize {
        let x = max(0, (image.size.width * scale - 320) / 2)
        let y = max(0, (image.size.height * scale - 320) / 2)
        return CGSize(width: max(-x, min(x, value.width)), height: max(-y, min(y, value.height)))
    }
    var body: some View {
        VStack(spacing: 18) {
            Text("裁剪头像").font(.title2.bold())
            Text("拖动图片选择位置，滑动缩放；圆圈内的部分就是头像。").foregroundStyle(.secondary)
            Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(offset).frame(width: 320, height: 320).clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 2))
                .contentShape(Circle()).gesture(
                    DragGesture().onChanged { value in
                        offset = capped(
                            CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height))
                    }.onEnded { _ in dragStart = offset })
            HStack {
                Text("缩放")
                Slider(value: $zoom, in: 1...5)
                Button("重置") {
                    zoom = 1
                    offset = .zero
                    dragStart = .zero
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            cropActions
        }.padding(24).frame(maxWidth: 760, maxHeight: .infinity).onChange(of: zoom) { _, _ in
            offset = capped(offset)
            dragStart = offset
        }
    }

    private var cropActions: some View {
        HStack {
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("使用裁剪结果") {
                do {
                    guard let data = AvatarCropRenderer.png(image: image, zoom: zoom, offset: offset) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let url = try LocalAssetFiles.saveAvatarDraft(data)
                    save(url)
                    dismiss()
                } catch { failure = "无法保存裁剪结果：" + error.localizedDescription }
            }.keyboardShortcut(.defaultAction)
        }
    }
}

import SwiftUI
import AppKit

struct ProductPhotoControls: View {
    @EnvironmentObject var store: GearStore
    @Binding var photo: String?
    @Binding var extras: GearExtras
    @State private var request: PhotoRequest?
    private var savedOriginal: GearAttachment? { extras.attachments.last { $0.title == "修图原图" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            photoSelection
            Text("导入后自动统一为 1024 × 1024，可预览抠图、白底与阴影。")
                .font(.caption).foregroundStyle(.secondary)
            if let savedOriginal {
                Button("恢复原图") {
                    photo = savedOriginal.file
                    extras.attachments.removeAll { $0.id == savedOriginal.id }
                }
            }
        }
        .sheet(item: $request) { request in
            ProductPhotoEditor(root: store.root.appendingPathComponent("Photos"), source: request.source) { filename in
                extras.attachments.append(GearAttachment(title: "修图原图", file: request.source, isImage: true))
                photo = filename
            }
        }
    }

    private var photoSelection: some View {
        HStack {
            GearPhoto(filename: photo).frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 8) {
                Button("设置主照片…") {
                    if let name = store.choosePhoto() { request = PhotoRequest(source: name) }
                }
                if let photo {
                    Button("白底与规格…") { request = PhotoRequest(source: photo) }
                }
            }
            if photo != nil { Button("取消主照片") { photo = nil } }
        }
    }
}

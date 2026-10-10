import SwiftUI
import AppKit

struct FullGearDetail: View {
    @EnvironmentObject var store: GearStore
    let gear: Gear
    let edit: () -> Void
    let open: (UUID) -> Void
    let child: () -> Void
    @State var duplicate = false
    @State private var photoRequest: PhotoRequest?
    var detail: GearExtras { store.inventory.extras(gear.id) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                equipmentHeading
                HStack {
                    Button("复制") { duplicate = true }
                }
                if !detail.description.isEmpty {
                    GroupBox("描述") {
                        Text(.init(detail.description)).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                basicFacts
                let children = store.inventory.children(of: gear.id).filter {
                    !store.inventory.extras($0.id).isLocation
                }
                if !children.isEmpty {
                    GroupBox("包含的装备") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(children) { record in Button(record.name) { open(record.id) } }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                GroupBox("购买信息") {
                    VStack(spacing: 10) {
                        field("购买价格", store.money(gear.purchasePrice))
                        field(
                            "渠道／日期",
                            [gear.purchaseFrom, gear.purchaseDate].filter { !$0.isEmpty }.joined(separator: " · "))
                    }.padding(8)
                }
                if !detail.attachments.isEmpty { attachmentGallery }
                if !gear.notes.isEmpty {
                    GroupBox("笔记") {
                        Text(.init(gear.notes)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
                HStack {
                    Spacer()
                    Button(gear.trashed ? "从回收站恢复" : "移至回收站") {
                        _ = store.changeRecords([gear.id], trash: !gear.trashed)
                    }
                }
            }.padding(24)
        }
        .sheet(isPresented: $duplicate) { DuplicateEditor(original: gear).environmentObject(store) }
        .sheet(item: $photoRequest) { request in
            ProductPhotoEditor(root: store.root.appendingPathComponent("Photos"), source: request.source) { filename in
                if !store.applyProductPhoto(for: gear.id, source: request.source, result: filename) {
                    store.error = store.error ?? "照片保存失败，原图已保留。"
                }
            }
        }

    }
    var attachmentGallery: some View {
        GroupBox("照片与附件") {
            VStack(alignment: .leading, spacing: 12) {
                attachmentThumbnails
                ForEach(detail.attachments) { attachment in
                    HStack {
                        Image(systemName: attachment.isImage ? "photo" : "doc")
                        Text(attachment.title)
                        Spacer()
                        Button("打开") { NSWorkspace.shared.open(store.attachmentURL(attachment)) }
                        Button("导出") { store.exportAttachment(attachment) }
                    }
                }
            }.padding(8)
        }
    }
    func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(name).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value.isEmpty ? "未填写" : value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var equipmentHeading: some View {
        HStack(alignment: .top, spacing: 18) {
            GearPhoto(filename: gear.photo).frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(gear.name).font(.title.bold()).textSelection(.enabled)
                Text("资产 #\(detail.assetID) · " + (detail.isLocation ? "位置" : gear.status)).foregroundStyle(.secondary)
                if let parent = detail.parentID, !store.inventory.extras(parent).isLocation {
                    Button(store.inventory.gear.first { $0.id == parent }?.name ?? "父级装备") { open(parent) }.buttonStyle(
                        .link)
                }
                HStack {
                    Button("编辑", action: edit)
                    Button("创建子装备", action: child)
                    Button {
                        _ = store.toggleFavorite(gear.id)
                    } label: {
                        Label(
                            store.inventory.isFavorite(gear.id) ? "已收藏" : "收藏",
                            systemImage: store.inventory.isFavorite(gear.id) ? "star.fill" : "star")
                    }
                    .help(store.inventory.isFavorite(gear.id) ? "取消收藏" : "收藏装备")
                }
                if detail.attachments.contains(where: { $0.title == "修图原图" }) {
                    Button("恢复原图") { _ = store.restoreProductPhoto(for: gear.id) }
                }
            }
        }
    }

    private var attachmentThumbnails: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
            ForEach(detail.attachments.filter(\.isImage)) { attachment in
                if let image = NSImage(contentsOf: store.attachmentURL(attachment)) {
                    VStack {
                        Image(nsImage: image).resizable().scaledToFit().frame(height: 90).onTapGesture {
                            NSWorkspace.shared.open(store.attachmentURL(attachment))
                        }
                        Text(attachment.title).font(.caption).lineLimit(1)
                        Button("设为主图") {
                            do {
                                let name = UUID().uuidString + "." + URL(fileURLWithPath: attachment.file).pathExtension
                                try LocalAssetFiles.copy(
                                    from: store.attachmentURL(attachment), to: store.photoURL(name))
                                photoRequest = PhotoRequest(source: name)
                            } catch { store.error = error.localizedDescription }
                        }.font(.caption)
                    }
                }
            }
        }
    }

    private var basicFacts: some View {
        GroupBox("基本资料") {
            VStack(spacing: 10) {
                field("分类", gear.category)
                if !GearSubcategories.children(of: gear.category).isEmpty {
                    field("子分类", store.inventory.subcategory(for: gear))
                }
                field("品牌／型号", [gear.brand, gear.model].filter { !$0.isEmpty }.joined(separator: " · "))
                field("数量", gear.quantity.formatted())
                field("单件重量", gear.weight.formatted() + " g")
            }.padding(8)
        }
    }
}

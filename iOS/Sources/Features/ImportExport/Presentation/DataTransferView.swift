import SwiftUI
import UniformTypeIdentifiers

struct DataView: View {
    @EnvironmentObject private var library: GearLibrary
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var pendingImport: URL?
    var body: some View {
        NavigationStack {
            List {
                Section("应用功能") {
                    NavigationLink { SettingsView().environmentObject(library) } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    NavigationLink { GearTrashView().environmentObject(library) } label: {
                        Label("回收站", systemImage: "trash")
                    }
                }
                Section("资料迁移与备份") {
                    Button { importing = true } label: { Label("从 Mac 导入完整装备库", systemImage: "square.and.arrow.down") }
                    Button {
                        exportURL = library.backupArchiveURL()
                        exporting = exportURL != nil
                    } label: { Label("导出完整备份（含照片附件）", systemImage: "square.and.arrow.up") }
                }
                Section("说明") {
                    Text("ZIP 完整备份包含装备、打包清单、路线、设置、徒步记录、照片和附件。也可直接选择 Mac 导出的 inventory.json；将同级 Photos、Files、Avatars 文件夹一起保存在旁边即可带回附件。导入会替换本机资料；手机与 Mac 之间通过文件传递，不会自动联网同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("装备条目", value: "\(library.activeGear.count)")
                    LabeledContent("徒步记录", value: "\(library.hikeHistory.count)")
                    LabeledContent("数据文件", value: "inventory.json")
                }
            }.navigationTitle("资料与同步")
                .scrollContentBackground(.hidden)
                .background(OutdoorPalette.background)
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zip]) { result in
                    if case .success(let url) = result { pendingImport = url }
                    if case .failure(let error) = result { library.alert = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: JSONFile(url: exportURL), contentType: .zip, defaultFilename: "户外装备库完整备份") { result in
                    if case .failure(let error) = result { library.alert = error.localizedDescription }
                    if case .success = result { library.alert = "装备库已导出。" }
                }
                .confirmationDialog("替换 iPhone 资料？", isPresented: Binding(
                    get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
                    Button("替换并导入", role: .destructive) {
                        if let pendingImport { library.importFile(pendingImport) }
                        pendingImport = nil
                    }
                    Button("取消", role: .cancel) { pendingImport = nil }
                } message: {
                    Text("导入会替换这部手机当前的装备、打包清单、路线、设置和徒步记录。建议先导出备份。")
                }
                .alert("户外装备库", isPresented: Binding(get: { library.alert != nil }, set: { if !$0 { library.alert = nil } })) {
                    Button("好", role: .cancel) { library.alert = nil }
                } message: { Text(library.alert ?? "") }
        }
    }
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .zip] }
    let data: Data
    init(url: URL?) { data = url.flatMap { try? Data(contentsOf: $0) } ?? Data("{}".utf8) }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

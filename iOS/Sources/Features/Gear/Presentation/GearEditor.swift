import SwiftUI
import PhotosUI
import UIKit

struct GearEditor: View {
    @EnvironmentObject private var library: GearLibrary
    @Environment(\.dismiss) private var dismiss
    @State var gear: Gear
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    private let categories = ["背包与收纳", "帐篷与睡眠", "服装与配饰", "鞋袜与行走", "炊具与饮水", "照明与电子", "工具与急救", "洗漱与杂项"]
    var body: some View {
        NavigationStack {
            Form {
                Section("装备照片") {
                    HStack(spacing: 14) {
                        Group {
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                Image(systemName: "backpack").font(.largeTitle).foregroundStyle(OutdoorPalette.accent)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(OutdoorPalette.glassTint)
                            }
                        }.frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 14))
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(gear.photo == nil ? "选择照片" : "更换照片", systemImage: "photo")
                        }
                    }
                }
                TextField("装备名称", text: $gear.name)
                TextField("品牌", text: $gear.brand)
                TextField("型号", text: $gear.model)
                Picker("分类", selection: $gear.category) { ForEach(categories, id: \.self) { Text($0) } }
                TextField("数量", value: $gear.quantity, format: .number).keyboardType(.decimalPad)
                TextField("单件重量（克）", value: $gear.weight, format: .number).keyboardType(.decimalPad)
                TextField("购买总价（元）", value: $gear.purchasePrice, format: .number).keyboardType(.decimalPad)
                TextField("购买来源", text: $gear.purchaseFrom)
                TextField("购买日期", text: $gear.purchaseDate, prompt: Text("YYYY-MM-DD"))
                TextField("存放位置", text: $gear.location)
                Picker("状态", selection: $gear.status) {
                    ForEach(["可用", "维修中", "损坏"], id: \.self) { Text($0) }
                }
                TextField("标签", text: $gear.tags)
                TextField("备注", text: $gear.notes, axis: .vertical).lineLimit(3...6)
            }
            .navigationTitle("装备资料")
            .task(id: selectedPhoto) { await loadSelectedPhoto() }
            .task { loadSavedPhoto() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { library.saveGear(gear); dismiss() }.disabled(gear.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func loadSavedPhoto() {
        guard let name = gear.photo else { return }
        photo = UIImage(contentsOfFile: library.photoURL(for: name).path)
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto,
              let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              let savedName = library.savePhoto(data) else { return }
        gear.photo = savedName
        photo = UIImage(data: data)
    }
}

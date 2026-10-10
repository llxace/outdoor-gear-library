import SwiftUI
import AppKit

struct FullGearEditor: View {
    @EnvironmentObject var store: GearStore
    @EnvironmentObject var libraries: UserLibraries
    @State private var destinationID: UUID?
    @State private var destinationStore: GearStore?
    private var editingStore: GearStore { destinationStore ?? store }
    private var isNew: Bool { !store.inventory.gear.contains(where: { $0.id == draft.gear.id }) }
    @Environment(\.dismiss) var dismiss
    @State var draft: GearDraft
    @State var validation = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "添加装备" : "编辑装备").font(.title2.bold())
                Spacer()
            }.padding(20)
            equipmentForm
            if !validation.isEmpty { Text(validation).foregroundStyle(.red).padding(8) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存并继续添加") { save(another: true) }
                Button("保存") { save(another: false) }.keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 700, height: 780)
    }
    private func changeDestination(_ id: UUID) {
        guard id != (destinationID ?? libraries.selectedID), let next = libraries.library(for: id) else { return }
        do {
            let copied = try next.copyUnsavedGear(draft.gear, extras: draft.extras, from: editingStore)
            draft.gear = copied.0
            draft.extras = copied.1
            destinationID = id
            destinationStore = next
            validation = ""
        } catch { validation = "切换保存用户失败，已保留当前内容：\(error.localizedDescription)" }
    }
    var parentCandidates: [Gear] {
        let excluded = editingStore.inventory.descendants(of: draft.gear.id).union([draft.gear.id])
        return editingStore.inventory.gear.filter {
            !$0.trashed && !excluded.contains($0.id) && !editingStore.inventory.extras($0.id).isLocation
        }
    }
    func save(another: Bool) {
        draft.gear.name = draft.gear.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.gear.name.isEmpty, draft.extras.assetID >= 0 else {
            validation = "名称不能为空，资产编号不能为负数。"
            return
        }
        let succeeded = editingStore.save(draft.gear, extras: draft.extras)
        guard succeeded else {
            validation = editingStore.error ?? "保存失败"
            return
        }
        if another {
            let parent = draft.extras.parentID
            let location = draft.extras.isLocation
            draft = GearDraft()
            draft.extras.parentID = parent
            draft.extras.isLocation = location
            validation = ""
        } else {
            if let destinationID, destinationID != libraries.selectedID {
                let name = libraries.users.first { $0.id == destinationID }?.name ?? "所选用户"
                store.notice = "装备已保存到“\(name)”的装备库。"
            }
            dismiss()
        }
    }

    private var basicInformationSection: some View {
        Section("基本信息") {
            TextField("名称（必填）", text: $draft.gear.name)
            TextField("描述", text: $draft.extras.description, axis: .vertical)
            if !draft.extras.isLocation {
                TextField("品牌", text: $draft.gear.brand)
                TextField("型号", text: $draft.gear.model)
                Picker("分类", selection: $draft.gear.category) {
                    ForEach(editingStore.inventory.categories, id: \.self) { Text($0).tag($0) }
                }
                if !GearSubcategories.children(of: draft.gear.category).isEmpty {
                    Picker(
                        "子分类",
                        selection: Binding(
                            get: {
                                guard let value = draft.extras.subcategory else { return "" }
                                return GearSubcategories.resolved(for: draft.gear, stored: value)
                            }, set: { draft.extras.subcategory = $0.isEmpty ? nil : $0 })
                    ) {
                        Text("自动识别 · " + GearSubcategories.inferred(for: draft.gear)).tag("")
                        ForEach(GearSubcategories.children(of: draft.gear.category), id: \.self) { child in
                            Label {
                                Text(child)
                            } icon: {
                                GearCategoryIcon(name: child)
                            }.tag(child)
                        }
                    }
                }
                Picker(
                    "状态",
                    selection: Binding(
                        get: { draft.gear.status == "损坏" ? "可用" : draft.gear.status },
                        set: { draft.gear.status = $0 }
                    )
                ) { ForEach(["可用", "想买", "借出", "已出售"], id: \.self) { Text($0) } }
                Toggle(
                    "已损坏",
                    isOn: Binding(
                        get: { draft.gear.status == "损坏" },
                        set: { draft.gear.status = $0 ? "损坏" : "可用" }
                    ))
            }
            Picker("父级装备", selection: $draft.extras.parentID) {
                Text("无父级").tag(nil as UUID?)
                ForEach(parentCandidates) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("数量", value: $draft.gear.quantity, format: .number)
            TextField("单件重量（克）", value: $draft.gear.weight, format: .number)
            TextField("资产编号（0 为自动生成）", value: $draft.extras.assetID, format: .number)
        }
    }

    private var attachmentsSection: some View {
        Section("照片与附件") {
            ProductPhotoControls(photo: $draft.gear.photo, extras: $draft.extras).environmentObject(editingStore)
            ForEach($draft.extras.attachments) { $attachment in
                HStack {
                    Image(systemName: attachment.isImage ? "photo" : "doc")
                    TextField("附件名称", text: $attachment.title)
                    Button("打开") { NSWorkspace.shared.open(editingStore.attachmentURL(attachment)) }
                    Button("移除") { draft.extras.attachments.removeAll { $0.id == attachment.id } }
                }
            }
            Button("添加多张照片或任意附件…") { draft.extras.attachments += editingStore.importAttachments() }
        }
    }

    private var equipmentForm: some View {
        Form {
            Section("用户装备库") {
                if isNew {
                    Picker(
                        "保存到用户",
                        selection: Binding(get: { destinationID ?? libraries.selectedID }, set: changeDestination)
                    ) {
                        ForEach(libraries.users) { Text($0.name).tag($0.id) }
                    }
                } else {
                    LabeledContent("所属用户", value: libraries.currentUser.name)
                }
            }
            basicInformationSection
            attachmentsSection
            Section("购买信息") {
                TextField("购买价格（CNY，整条记录总价）", value: $draft.gear.purchasePrice, format: .number)
                TextField("购买渠道", text: $draft.gear.purchaseFrom)
                TextField("购买日期（YYYY-MM-DD）", text: $draft.gear.purchaseDate)
            }
            Section("笔记（支持 Markdown）") { TextEditor(text: $draft.gear.notes).frame(minHeight: 110) }
        }.formStyle(.grouped)
    }
}

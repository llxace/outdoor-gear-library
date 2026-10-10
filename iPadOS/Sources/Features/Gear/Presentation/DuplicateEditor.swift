import SwiftUI
import UIKit

struct DuplicateEditor: View {
    @EnvironmentObject var store: GearStore
    @Environment(\.dismiss) var dismiss
    let original: Gear
    @State var attachments = true
    @State var prefix = "副本 · "
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("复制：" + original.name).font(.title2.bold())
            Toggle("复制照片和附件", isOn: $attachments)
            TextField("名称前缀", text: $prefix)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("复制") {
                    let gear = store.duplicate(original, copyAttachments: attachments, prefix: prefix)
                    let detail = store.duplicateExtras(original, copyAttachments: attachments)
                    if store.save(gear, extras: detail) { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(maxWidth: 760, maxHeight: .infinity).onAppear {
            let settings = store.inventory.settings
            attachments = settings.copyAttachments
            prefix = settings.copyPrefix
        }
    }
}

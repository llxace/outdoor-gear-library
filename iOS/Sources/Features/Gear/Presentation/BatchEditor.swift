import SwiftUI
import AppKit

struct BatchEditor: View {
    @EnvironmentObject var store: GearStore
    @Environment(\.dismiss) var dismiss
    let ids: Set<UUID>
    @State var action = "状态"
    @State var status = "可用"
    @State var failure = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("批量操作 · \(ids.count) 条记录").font(.title2.bold())
            Picker("操作", selection: $action) { ForEach(["状态", "移至回收站", "恢复"], id: \.self) { Text($0) } }
            if action == "状态" {
                Picker("新状态", selection: $status) { ForEach(["可用", "想买", "借出", "损坏", "已出售"], id: \.self) { Text($0) } }
            }
            Text("操作会保存到本机，回收站记录可恢复。").font(.caption).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
            confirmationActions
        }.padding(24).frame(width: 470)
    }

    private var confirmationActions: some View {
        HStack {
            Button("取消") { dismiss() }
            Spacer()
            Button("应用") {
                let succeeded: Bool
                switch action {
                case "状态": succeeded = store.changeRecords(ids, status: status)
                case "移至回收站": succeeded = store.changeRecords(ids, trash: true)
                default: succeeded = store.changeRecords(ids, trash: false)
                }
                if succeeded { dismiss() } else { failure = store.error ?? "操作失败" }
            }.keyboardShortcut(.defaultAction)
        }
    }
}

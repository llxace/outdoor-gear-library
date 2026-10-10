import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: GearLibrary

    private var name: Binding<String> {
        Binding(get: { library.settingValue("name", default: "户外装备库") }, set: { library.updateSetting("name", value: $0) })
    }
    private var owner: Binding<String> {
        Binding(get: { library.settingValue("owner") }, set: { library.updateSetting("owner", value: $0) })
    }
    private var appearance: Binding<String> {
        Binding(get: { library.appearance }, set: { library.updateSetting("appearance", value: $0) })
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("颜色模式", selection: appearance) {
                    Text("跟随系统").tag("跟随系统")
                    Text("浅色").tag("浅色")
                    Text("深色").tag("深色")
                }
            }
            Section("资料库") {
                TextField("资料库名称", text: name)
                TextField("所有者", text: owner)
                LabeledContent("装备条目", value: "\(library.activeGear.count)")
                LabeledContent("徒步记录", value: "\(library.hikeHistory.count)")
            }
            Section("本机存储") {
                Text("资料仅保存在这部 iPhone 的应用目录中。使用“资料与同步”导出完整 JSON 备份，再将文件传到 Mac 导入。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(OutdoorPalette.background)
        .navigationTitle("设置")
    }

}

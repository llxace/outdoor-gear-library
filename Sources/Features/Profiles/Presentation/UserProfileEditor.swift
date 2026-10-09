import SwiftUI
import AppKit

struct UserProfileEditor: View {
    @EnvironmentObject var libraries: UserLibraries
    @Environment(\.dismiss) private var dismiss
    let user: LibraryUser
    @State private var name = ""
    @State private var avatar: URL?
    @State private var cropping: AvatarCropSource?
    @State private var temporaryAvatars: [URL] = []
    @State private var removeAvatar = false
    @State private var failure = ""
    private var isExisting: Bool { libraries.users.contains(where: { $0.id == user.id }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isExisting ? "编辑个人资料" : "新建用户").font(.title2.bold())
            avatarSettings
            TextField("用户名", text: $name).textFieldStyle(.roundedBorder)
            Text(isExisting ? "头像和用户名保存后生效，装备及清单仍属于这个用户。" : "新用户从空装备库开始，资料独立保存。")
                .font(.callout).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
            profileActions
        }.padding(24).frame(width: 480).onAppear { name = user.name }
            .sheet(item: $cropping) { source in
                if let image = NSImage(contentsOf: source.url) {
                    AvatarCropEditor(image: image) { url in
                        avatar = url
                        temporaryAvatars.append(url)
                        removeAvatar = false
                    }
                }
            }
            .onDisappear { LocalAssetFiles.removeDrafts(temporaryAvatars) }
    }

    private var avatarSettings: some View {
        HStack(spacing: 18) {
            Group {
                if let avatar, let image = NSImage(contentsOf: avatar) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if removeAvatar {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
                } else {
                    UserAvatar(user: user, size: 80)
                }
            }.frame(width: 80, height: 80).clipShape(Circle())
            VStack(alignment: .leading, spacing: 10) {
                Button("选择头像…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url {
                        if NSImage(contentsOf: url) != nil {
                            cropping = AvatarCropSource(url: url)
                            failure = ""
                        } else {
                            failure = "这张图片无法读取，请选择其他图片。"
                        }
                    }
                }
                if let current = avatar ?? (removeAvatar ? nil : libraries.avatarURL(for: user)) {
                    Button("裁剪头像…") { cropping = AvatarCropSource(url: current) }
                }
                Button("使用默认头像") {
                    avatar = nil
                    removeAvatar = true
                }
            }
        }
    }

    private var profileActions: some View {
        HStack {
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button(isExisting ? "保存资料" : "创建并切换") {
                if libraries.saveUser(
                    name: name, renaming: isExisting ? user.id : nil, avatarURL: avatar, removeAvatar: removeAvatar)
                {
                    dismiss()
                } else {
                    failure = libraries.error ?? "保存失败"
                    libraries.error = nil
                }
            }.keyboardShortcut(.defaultAction)
        }
    }
}

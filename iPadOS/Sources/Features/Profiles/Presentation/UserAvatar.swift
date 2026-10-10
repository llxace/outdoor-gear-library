import SwiftUI
import UIKit

struct UserAvatar: View {
    @EnvironmentObject var libraries: UserLibraries
    let user: LibraryUser
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let url = libraries.avatarURL(for: user), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityLabel(user.name + "的头像")
    }
}

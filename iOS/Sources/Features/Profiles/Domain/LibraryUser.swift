import Foundation

struct LibraryUser: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var avatarFile: String?
}

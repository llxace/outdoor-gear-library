import Foundation

struct UserCatalog: Codable {
    var users: [LibraryUser]
    var selectedID: UUID
}

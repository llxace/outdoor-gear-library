import Foundation

struct GearAttachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var file: String
    var isImage = false
}

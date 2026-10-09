import Foundation

struct GearTag: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var description = ""
    var color = "绿色"
    var parentID: UUID?
}

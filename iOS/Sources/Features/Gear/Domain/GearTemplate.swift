import Foundation

struct GearTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var gear = Gear()
    var extras = GearExtras()
}

import Foundation

struct GearExtras: Codable, Equatable {
    var isLocation = false
    var assetID = 0
    var subcategory: String?
    var importRef = ""
    var description = ""
    var parentID: UUID?
    var locationOverrideID: UUID?
    var attachments: [GearAttachment] = []
}

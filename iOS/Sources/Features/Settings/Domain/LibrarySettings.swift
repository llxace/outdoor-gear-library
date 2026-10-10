import Foundation

struct LibrarySettings: Codable, Equatable {
    var name = "户外装备库"
    var currency = "CNY"
    var owner = ""
    var appearance = "跟随系统"
    var autoAssetID = true
    var includeChildLocations = true
    var copyAttachments = true
    var copyPrefix = "副本 · "
}

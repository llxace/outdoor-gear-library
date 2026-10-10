import SwiftUI
import AppKit

func chooseHistoricalTrack() throws -> HistoricalTrackImport? {
    let panel = NSOpenPanel()
    panel.title = "导入以前走过的轨迹"
    panel.message = "选择两步路或其他平台导出的 GPX/KML；下一步核对徒步日期和携带装备。"
    panel.allowedFileTypes = ["gpx", "kml"]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return try LibraryTransferFiles.historicalTrack(at: url)
}

import Foundation

extension GearLibrary {
    func importTrackFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let route = try TrailFileReader.read(Data(contentsOf: url), filename: url.lastPathComponent)
            selectRoute(route)
            alert = "已导入轨迹：\(route.name) · \(route.distance)"
        } catch {
            alert = "轨迹导入失败：\(error.localizedDescription)"
        }
    }
}

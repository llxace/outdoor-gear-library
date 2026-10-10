import Foundation

enum TrailFileReader {
    static func read(_ data: Data, filename: String) throws -> RouteSnapshot {
        guard data.count <= 10_000_000 else { throw failure("轨迹文件超过 10 MB，请先精简。") }
        let parserDelegate = TrackParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = parserDelegate
        let parsed = parser.parse()
        if let problem = parserDelegate.problem { throw failure(problem) }
        guard parsed, ["gpx", "kml"].contains(parserDelegate.root) else {
            throw failure("文件不是有效的 GPX 或 KML 轨迹。")
        }
        let segments = parserDelegate.segments.filter { $0.count >= 2 }
        let points = segments.flatMap { $0 }
        guard points.count >= 2 else { throw failure("文件中没有可显示的线路轨迹。") }
        let center = RoutePoint(
            lat: (points.map(\.lat).min()! + points.map(\.lat).max()!) / 2,
            lon: (points.map(\.lon).min()! + points.map(\.lon).max()!) / 2)
        let kilometers = length(of: segments) / 1_000
        let name = parserDelegate.title.isEmpty ? (filename as NSString).deletingPathExtension : parserDelegate.title
        return RouteSnapshot(
            id: Int64(Date().timeIntervalSince1970 * 1_000_000), name: name, area: "导入轨迹",
            distance: String(format: "%.1f km（轨迹估算）", kilometers), center: center,
            segments: segments, importedFile: filename)
    }

    private static func length(of segments: [[RoutePoint]]) -> Double {
        segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { meters, pair in
                let a = pair.0, b = pair.1
                let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
                let h = pow(sin((lat2 - lat1) / 2), 2)
                    + cos(lat1) * cos(lat2) * pow(sin((b.lon - a.lon) * .pi / 360), 2)
                return meters + 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
            }
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TrailFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class TrackParser: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var text = ""
    private var segment: [RoutePoint] = []
    var segments: [[RoutePoint]] = []
    var title = ""
    var root = ""
    var problem: String?
    private var pointCount = 0

    func append(_ point: RoutePoint, parser: XMLParser) {
        guard point.lat.isFinite, point.lon.isFinite, (-90...90).contains(point.lat), (-180...180).contains(point.lon) else {
            problem = "轨迹包含无效经纬度。"
            parser.abortParsing()
            return
        }
        pointCount += 1
        guard pointCount <= 50_000 else {
            problem = "轨迹超过 50,000 个点，暂时无法导入。"
            parser.abortParsing()
            return
        }
        segment.append(point)
    }

    func parseCoordinates(_ value: String, parser: XMLParser) {
        for token in value.split(whereSeparator: \.isWhitespace) {
            let pair = token.split(separator: ",")
            guard pair.count >= 2, let lon = Double(pair[0]), let lat = Double(pair[1]) else {
                problem = "KML 轨迹坐标格式不正确."
                parser.abortParsing()
                return
            }
            append(RoutePoint(lat: lat, lon: lon), parser: parser)
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        text = ""
        if path.count == 1 { root = name }
        if ["trkseg", "rte", "LineString", "Track"].contains(name) { segment = [] }
        if ["trkpt", "rtept"].contains(name) {
            guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else {
                problem = "轨迹点缺少经纬度。"
                parser.abortParsing()
                return
            }
            append(RoutePoint(lat: lat, lon: lon), parser: parser)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(data: block, encoding: .utf8) ?? "" }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.dropLast().last ?? ""
        if name == "name", title.isEmpty, ["metadata", "trk", "rte", "Document", "Placemark"].contains(parent) {
            title = value
        }
        if name == "coordinates", path.contains("LineString") { parseCoordinates(value, parser: parser) }
        if name == "coord", path.contains("Track") {
            let pair = value.split(whereSeparator: \.isWhitespace)
            guard pair.count >= 2, let lon = Double(pair[0]), let lat = Double(pair[1]) else {
                problem = "KML 轨迹坐标格式不正确。"
                parser.abortParsing()
                return
            }
            append(RoutePoint(lat: lat, lon: lon), parser: parser)
        }
        if ["trkseg", "rte", "LineString", "Track"].contains(name) {
            segments.append(segment)
            segment = []
        }
        if !path.isEmpty { path.removeLast() }
        text = ""
    }
}

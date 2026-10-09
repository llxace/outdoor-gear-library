import Foundation

/// Reads track geometry only; waypoint notes and external resources are not imported.
final class TrailFileReader: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var text = ""
    private var title = ""
    private var segment: [TrailPoint] = []
    private var segments: [[TrailPoint]] = []
    private var pointCount = 0
    private var problem: String?
    private var root = ""

    static func read(_ data: Data, filename: String) throws -> HikingRoute {
        guard data.count <= 10_000_000 else { throw failure("轨迹文件超过 10 MB，请先精简。") }
        let reader = TrailFileReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse()
        if let problem = reader.problem { throw failure(problem) }
        guard parsed, ["gpx", "kml"].contains(reader.root) else { throw failure("文件不是有效的 GPX 或 KML 轨迹。") }
        let segments = reader.segments.filter { $0.count >= 2 }
        let points = segments.flatMap { $0 }
        guard points.count >= 2 else { throw failure("文件中没有可显示的线路；仅有位置标记不能作为徒步轨迹。") }
        let center = TrailPoint(
            lat: (points.map(\.lat).min()! + points.map(\.lat).max()!) / 2,
            lon: (points.map(\.lon).min()! + points.map(\.lon).max()!) / 2)
        let meters = distance(of: segments)
        return HikingRoute(
            id: Int64(Date().timeIntervalSince1970 * 1_000_000),
            name: reader.title.isEmpty ? (filename as NSString).deletingPathExtension : reader.title,
            area: "导入轨迹", center: center,
            distance: (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km（轨迹估算）",
            segments: segments, importedFile: filename)
    }
    private static func distance(of segments: [[TrailPoint]]) -> Double {
        var meters = 0.0
        for segment in segments {
            for (a, b) in zip(segment, segment.dropFirst()) {
                let lat1 = a.lat * .pi / 180
                let lat2 = b.lat * .pi / 180
                let h =
                    pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((b.lon - a.lon) * .pi / 360), 2)
                meters += 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
            }
        }
        return meters
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TrailFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func append(_ point: TrailPoint, parser: XMLParser) {
        guard point.isValid else {
            problem = "轨迹包含无效经纬度。"
            parser.abortParsing()
            return
        }
        pointCount += 1
        guard pointCount <= 50000 else {
            problem = "轨迹超过 50,000 个点，暂时无法导入。"
            parser.abortParsing()
            return
        }
        segment.append(point)
    }
    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        path.append(name)
        text = ""
        if path.count == 1 { root = name }
        if ["trkseg", "rte", "LineString", "Track"].contains(name) { segment = [] }
        if ["trkpt", "rtept"].contains(name) {
            guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init)
            else {
                problem = "轨迹点缺少经纬度。"
                parser.abortParsing()
                return
            }
            append(TrailPoint(lat: lat, lon: lon), parser: parser)
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(data: block, encoding: .utf8) ?? "" }
    private func appendCoordinates(_ value: String, parser: XMLParser) {
        for token in value.split(whereSeparator: { $0.isWhitespace }) {
            let pair = token.split(separator: ",")
            guard pair.count >= 2, let lon = Double(pair[0]), let lat = Double(pair[1]) else {
                problem = "KML 轨迹坐标格式不正确。"
                parser.abortParsing()
                break
            }
            append(
                TrailPoint(lat: lat, lon: lon, elevation: pair.count > 2 ? Double(pair[2]) : nil), parser: parser)
        }
    }
    private func readMetadata(name: String, value: String) {
        if name == "name", title.isEmpty, let parent = path.dropLast().last,
            ["metadata", "trk", "rte", "Document", "Placemark"].contains(parent)
        {
            title = value
        }
        if name == "ele", ["trkpt", "rtept"].contains(path.dropLast().last ?? ""), let height = Double(value),
            height.isFinite, !segment.isEmpty
        {
            segment[segment.count - 1].elevation = height
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        readMetadata(name: name, value: value)
        if name == "coordinates", path.contains("LineString") {
            appendCoordinates(value, parser: parser)
        }
        if name == "coord", path.contains("Track") {
            let pair = value.split(whereSeparator: { $0.isWhitespace })
            guard pair.count >= 2, let lon = Double(pair[0]), let lat = Double(pair[1]) else {
                problem = "KML 轨迹坐标格式不正确。"
                parser.abortParsing()
                return
            }
            append(TrailPoint(lat: lat, lon: lon, elevation: pair.count > 2 ? Double(pair[2]) : nil), parser: parser)
        }
        if ["trkseg", "rte", "LineString", "Track"].contains(name) {
            segments.append(segment)
            segment = []
        }
        path.removeLast()
        text = ""
    }
}

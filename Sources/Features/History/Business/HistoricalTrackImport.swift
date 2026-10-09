import Foundation

struct HistoricalTrackImport {
    let route: HikingRoute
    let recordedDate: Date?
    static func read(_ data: Data, filename: String) throws -> HistoricalTrackImport {
        let route = try TrailFileReader.read(data, filename: filename)
        let reader = HistoricalTrackDateReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        _ = parser.parse()
        return HistoricalTrackImport(route: route, recordedDate: reader.trackDate ?? reader.metadataDate)
    }
    var record: HikeRecord {
        var record = HikeRecord()
        record.title = route.name
        record.routeName = route.name
        record.route = route
        record.distance = route.distance
        if let recordedDate { record.date = recordedDate }
        return record
    }
}

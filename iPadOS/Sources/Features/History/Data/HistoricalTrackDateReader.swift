import SwiftUI
import UIKit

final class HistoricalTrackDateReader: NSObject, XMLParserDelegate {
    var trackDate: Date?
    var metadataDate: Date?
    private var path: [String] = []
    private var text = ""
    private let formatter = ISO8601DateFormatter()
    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        path.append(elementName.lowercased())
        text = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "time" || name == "when" {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: value)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: value)
            }
            if let date {
                if path.contains("trkpt") || path.contains("rtept") || (name == "when" && path.contains("track")) {
                    trackDate = trackDate.map { min($0, date) } ?? date
                } else if path.contains("metadata") {
                    metadataDate = date
                }
            }
        }
        _ = path.popLast()
        text = ""
    }
}

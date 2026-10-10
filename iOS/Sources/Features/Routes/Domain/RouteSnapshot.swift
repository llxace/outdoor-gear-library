import CoreLocation
import Foundation

struct RoutePoint: Codable {
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

struct RouteSnapshot: Codable, Identifiable {
    let id: Int64
    let name: String
    let area: String
    let distance: String
    let center: RoutePoint
    var segments: [[RoutePoint]] = []
    var importedFile: String?

    enum CodingKeys: String, CodingKey { case id, name, area, distance, center, segments, importedFile }

    init(id: Int64, name: String, area: String, distance: String, center: RoutePoint, segments: [[RoutePoint]], importedFile: String? = nil) {
        self.id = id
        self.name = name
        self.area = area
        self.distance = distance
        self.center = center
        self.segments = segments
        self.importedFile = importedFile
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        area = try values.decode(String.self, forKey: .area)
        distance = try values.decode(String.self, forKey: .distance)
        center = try values.decode(RoutePoint.self, forKey: .center)
        segments = try values.decodeIfPresent([[RoutePoint]].self, forKey: .segments) ?? []
        importedFile = try values.decodeIfPresent(String.self, forKey: .importedFile)
    }
}

struct RouteCatalogEntry: Decodable {
    let route: RouteSnapshot
}

struct RouteCatalog: Decodable {
    let entries: [RouteCatalogEntry]
}

extension GearLibrary {
    var selectedRouteSnapshot: RouteSnapshot? {
        guard let selectedRoute,
              let data = try? JSONSerialization.data(withJSONObject: selectedRoute) else { return nil }
        return try? JSONDecoder().decode(RouteSnapshot.self, from: data)
    }

    func selectRoute(_ route: RouteSnapshot?) {
        if let route, let data = try? JSONEncoder().encode(route),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            inventory["selectedRoute"] = raw
        } else {
            inventory.removeValue(forKey: "selectedRoute")
        }
        save()
    }
}

import Foundation

@MainActor struct LiveRouteSearch: RouteSearching {
    func details(_ route: HikingRoute) async throws -> HikingRoute { try await TripService.details(route) }
    func namedRoutes(_ query: String) async throws -> [HikingRoute] { try await TripService.namedRoutes(query) }
    func places(_ query: String) async throws -> [TrailPlace] { try await TripService.places(query) }
    func routes(near place: TrailPlace, radius: Int) async throws -> [HikingRoute] {
        try await TripService.routes(near: place, radius: radius)
    }
}

struct TrackFileRepository {
    static func read(_ url: URL) throws -> HikingRoute {
        try TrailFileReader.read(Data(contentsOf: url), filename: url.lastPathComponent)
    }
}

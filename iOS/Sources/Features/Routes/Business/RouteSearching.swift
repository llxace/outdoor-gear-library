import Foundation

@MainActor protocol RouteSearching {
    func details(_ route: HikingRoute) async throws -> HikingRoute
    func namedRoutes(_ query: String) async throws -> [HikingRoute]
    func places(_ query: String) async throws -> [TrailPlace]
    func routes(near place: TrailPlace, radius: Int) async throws -> [HikingRoute]
}

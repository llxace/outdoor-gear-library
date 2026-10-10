import Foundation

@MainActor struct LiveTripConditions: TripConditionsProviding {
    func terrain(_ route: HikingRoute) async throws -> RouteTerrain? { try await TripService.terrain(route) }
    func forecast(at point: TrailPoint, departure: Date) async throws -> WeatherForecast {
        try await WeatherService.forecast(at: point, departure: departure)
    }
    func outlook(at point: TrailPoint) async throws -> SeasonalOutlook {
        try await WeatherService.seasonalOutlook(at: point)
    }
}

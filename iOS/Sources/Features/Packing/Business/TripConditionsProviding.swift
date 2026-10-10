import Foundation

@MainActor protocol TripConditionsProviding {
    func terrain(_ route: HikingRoute) async throws -> RouteTerrain?
    func forecast(at point: TrailPoint, departure: Date) async throws -> WeatherForecast
    func outlook(at point: TrailPoint) async throws -> SeasonalOutlook
}

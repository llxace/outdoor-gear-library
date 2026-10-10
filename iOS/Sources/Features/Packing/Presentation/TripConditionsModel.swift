import Foundation
import Combine

@MainActor final class TripConditionsModel: ObservableObject {
    @Published var terrain: RouteTerrain?
    @Published var terrainError: String?
    @Published var forecast: WeatherForecast?
    @Published var outlook: SeasonalOutlook?
    @Published var outlookError: String?
    @Published var outlookLoading = false
    @Published var outsideForecastRange = false
    @Published var departureHasPassed = false
    @Published var updated: Date?
    @Published var loading = false
    @Published var error: String?
    private let provider: any TripConditionsProviding
    private let now: () -> Date

    init(provider: (any TripConditionsProviding)? = nil, now: @escaping () -> Date = { Date() }) {
        self.provider = provider ?? LiveTripConditions()
        self.now = now
    }
    func loadTerrain(route: HikingRoute?) async {

        terrain = nil
        terrainError = nil
        guard let route else { return }
        do {
            let result = try await provider.terrain(route)
            try Task.checkCancellation()
            terrain = result
        } catch { if !Task.isCancelled { terrainError = "海拔查询失败，可稍后重新打开页面" } }

    }
    func loadForecast(route: HikingRoute?, departure: Date) async {

        forecast = nil
        updated = nil
        error = nil
        outsideForecastRange = false
        let currentTime = now()
        let currentHour = Calendar.current.dateInterval(of: .hour, for: currentTime)?.start ?? currentTime
        departureHasPassed = departure < currentHour
        guard let route else {
            loading = false
            return
        }
        if departureHasPassed {
            error = "所选出发时间已过去，请调整日期和时间后重新查询天气。"
            loading = false
            return
        }
        loading = true
        do {
            let result = try await provider.forecast(at: route.center, departure: departure)
            try Task.checkCancellation()
            forecast = result
            updated = Date()
            loading = false
        } catch {
            if !Task.isCancelled {
                outsideForecastRange = (error as NSError).domain == "TripPlanning" && (error as NSError).code == 2
                self.error = error.localizedDescription
                loading = false
            }
        }

    }
    func loadOutlook(route: HikingRoute?) async {

        outlook = nil
        outlookError = nil
        guard let route else {
            outlookLoading = false
            return
        }
        outlookLoading = true
        do {
            let result = try await provider.outlook(at: route.center)
            try Task.checkCancellation()
            outlook = result
            outlookLoading = false
        } catch {
            if !Task.isCancelled {
                outlookError = error.localizedDescription
                outlookLoading = false
            }
        }

    }
}

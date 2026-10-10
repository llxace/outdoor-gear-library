import Foundation
import SwiftUI

@MainActor
final class TripWeatherModel: ObservableObject {
    @Published private(set) var day: Day?
    @Published private(set) var days: [Day] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private let service: TripWeatherProviding

    init(service: TripWeatherProviding = OpenMeteoWeatherService()) {
        self.service = service
    }

    func load(route: RouteSnapshot?, date: Date) async {
        guard let route else { day = nil; days = []; message = "选择路线后查看出发地天气"; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let forecast = try await service.forecast(
                latitude: route.center.lat, longitude: route.center.lon, date: date)
            days = forecast.days
            day = forecast.day(on: date)
            if day == nil { message = "暂无所选日期的天气数据" }
        } catch {
            day = nil
            days = []
            message = error.localizedDescription
        }
    }
}

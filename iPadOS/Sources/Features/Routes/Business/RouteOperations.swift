import Foundation

enum RouteOperations {
    static func selectRoute(_ route: HikingRoute?, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.selectedRoute = route
        return next
    }
}

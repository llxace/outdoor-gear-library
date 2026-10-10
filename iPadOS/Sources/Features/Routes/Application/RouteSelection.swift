import Foundation

extension GearStore {
    @discardableResult func selectRoute(_ route: HikingRoute?) -> Bool {
        return updateInventory { try RouteOperations.selectRoute(route, in: $0) }
    }
}

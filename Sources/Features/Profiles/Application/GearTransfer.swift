import Foundation

extension GearStore {
    func copyUnsavedGear(_ gear: Gear, extras: GearExtras, from source: GearStore) throws -> (Gear, GearExtras) {
        var transfer = GearAssetTransfer(source: source.root, destination: root)
        return try transfer.transfer(gear, extras: extras)
    }
}

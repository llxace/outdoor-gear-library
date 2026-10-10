import Foundation

extension GearLibrary {
    var appearance: String {
        (inventory["settings"] as? [String: Any])?["appearance"] as? String ?? "深色"
    }

    func settingValue(_ key: String, default defaultValue: String = "") -> String {
        (inventory["settings"] as? [String: Any])?[key] as? String ?? defaultValue
    }

    func updateSetting(_ key: String, value: Any) {
        var settings = inventory["settings"] as? [String: Any] ?? [:]
        settings[key] = value
        inventory["settings"] = settings
        save()
    }
}

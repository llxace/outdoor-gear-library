import Foundation

enum GearOperations {
    static func save(_ gear: Gear, extras: GearExtras, in inventory: Inventory) throws -> Inventory {
        try validate(gear, extras: extras, in: inventory)
        var next = inventory
        var detail = extras
        if detail.assetID == 0 && next.settings.autoAssetID {
            detail.assetID = (next.details.values.map(\.assetID).max() ?? 0) + 1
        }
        if detail.importRef.isEmpty { detail.importRef = gear.id.uuidString }
        var record = gear
        record.location = ""
        if let i = next.gear.firstIndex(where: { $0.id == gear.id }) {
            next.gear[i] = record
        } else {
            next.gear.append(record)
        }
        next.details[gear.id.uuidString] = detail
        for name in gear.tags.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        where !name.isEmpty && !next.labels.contains(where: { $0.name == name }) {
            next.labels.append(GearTag(name: name))
        }
        next.locations = next.places.map(\.name)
        return next
    }

    static func changeRecords(
        _ ids: Set<UUID>, status: String? = nil, parent: UUID? = nil,
        setParent: Bool = false, tags: String? = nil, trash: Bool? = nil, in inventory: Inventory
    ) throws -> Inventory {
        var next = inventory
        let targets = trash == nil ? ids : ids.reduce(into: ids) { $0.formUnion(inventory.descendants(of: $1)) }
        for i in next.gear.indices where targets.contains(next.gear[i].id) {
            let id = next.gear[i].id
            if let status { next.gear[i].status = status }
            if let tags { next.gear[i].tags = tags }
            if let trash { next.gear[i].trashed = trash }
            var detail = next.extras(id)
            if setParent {
                if let parent,
                    parent == id || next.descendants(of: id).contains(parent)
                        || (detail.isLocation && !next.extras(parent).isLocation)
                {
                    throw BusinessError("批量移动会产生无效层级，未修改任何记录。")
                }
                detail.parentID = parent
            }
            next.details[id.uuidString] = detail
        }
        next.locations = next.places.map(\.name)
        return next
    }

    static func saveTag(_ tag: GearTag, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        guard !tag.name.trimmingCharacters(in: .whitespaces).isEmpty, !tag.name.contains(","),
            !next.labels.contains(where: { $0.id != tag.id && $0.name == tag.name })
        else {
            throw BusinessError("标签名不能为空、重复或包含逗号。")
        }
        var cursor = tag.parentID
        var seen: Set<UUID> = [tag.id]
        while let id = cursor {
            if seen.contains(id) { throw BusinessError("标签层级不能形成循环。") }
            seen.insert(id)
            cursor = next.labels.first { $0.id == id }?.parentID
        }
        if let i = next.labels.firstIndex(where: { $0.id == tag.id }) {
            let oldName = next.labels[i].name
            for j in next.gear.indices {
                next.gear[j].tags = renamedTags(next.gear[j].tags, from: oldName, to: tag.name)
            }
            next.labels[i] = tag
            for i in next.templates.indices {
                next.templates[i].gear.tags = renamedTags(next.templates[i].gear.tags, from: oldName, to: tag.name)
            }
        } else {
            next.labels.append(tag)
        }
        return next
    }

    private static func renamedTags(_ tags: String, from oldName: String, to newName: String) -> String {
        tags.split(separator: ",").map {
            let name = $0.trimmingCharacters(in: .whitespaces)
            return name == oldName ? newName : name
        }.joined(separator: ", ")
    }

    static func removeTag(_ tag: GearTag, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.labels.removeAll { $0.id == tag.id }
        for i in next.labels.indices where next.labels[i].parentID == tag.id { next.labels[i].parentID = tag.parentID }
        for i in next.gear.indices {
            next.gear[i].tags = next.gear[i].tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0 != tag.name }.joined(separator: ", ")
        }
        for i in next.templates.indices {
            next.templates[i].gear.tags = next.templates[i].gear.tags.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { $0 != tag.name }.joined(separator: ", ")
        }
        return next
    }

    static func saveTemplate(_ template: GearTemplate, in inventory: Inventory) throws -> Inventory {
        guard !template.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw BusinessError("模板名称不能为空。") }
        var next = inventory
        if let i = next.templates.firstIndex(where: { $0.id == template.id }) {
            next.templates[i] = template
        } else {
            next.templates.append(template)
        }
        return next
    }

    static func removeTemplate(_ template: GearTemplate, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.templates.removeAll { $0.id == template.id }
        return next
    }

    static func saveSettings(_ settings: LibrarySettings, in inventory: Inventory) throws -> Inventory {
        var next = inventory
        next.settings = settings
        return next
    }

    static func ensureIdentifiers(in inventory: Inventory) throws -> Inventory {
        var next = inventory
        for gear in next.gear {
            var detail = next.extras(gear.id)
            if detail.assetID == 0 { detail.assetID = (next.details.values.map(\.assetID).max() ?? 0) + 1 }
            if detail.importRef.isEmpty { detail.importRef = gear.id.uuidString }
            next.details[gear.id.uuidString] = detail
        }
        return next
    }

    static func normalizeDates(in inventory: Inventory) throws -> Inventory {
        var next = inventory
        for i in next.gear.indices {
            next.gear[i].purchaseDate = normalizeDate(next.gear[i].purchaseDate)
        }
        return next
    }

    private static func normalizeDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let datePart = String(value.prefix(10))
        return formatter.date(from: datePart) != nil ? datePart : value
    }
    private static func validate(_ gear: Gear, extras: GearExtras, in inventory: Inventory) throws {
        guard !gear.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            gear.quantity.isFinite, gear.quantity > 0,
            [gear.weight, gear.purchasePrice].allSatisfy({ $0.isFinite && $0 >= 0 })
        else {
            throw BusinessError("名称不能为空，数量须大于 0，金额和重量须为非负数。")
        }
        let next = inventory
        let detail = extras
        if let parent = detail.parentID {
            guard parent != gear.id, !next.descendants(of: gear.id).contains(parent),
                let parentGear = next.gear.first(where: { $0.id == parent }), !parentGear.trashed,
                !detail.isLocation || next.extras(parent).isLocation
            else {
                throw BusinessError("父级无效：位置只能放在位置内，且不能形成循环。")
            }
        }
        if detail.assetID > 0
            && next.details.contains(where: { $0.key != gear.id.uuidString && $0.value.assetID == detail.assetID })
        {
            throw BusinessError("资产编号已被其他记录使用。")
        }
        if !detail.importRef.isEmpty
            && next.details.contains(where: { $0.key != gear.id.uuidString && $0.value.importRef == detail.importRef })
        {
            throw BusinessError("导入标识已被其他记录使用。")
        }
    }
}

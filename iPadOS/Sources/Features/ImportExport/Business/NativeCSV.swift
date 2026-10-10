import Foundation

enum NativeCSV {
    static let columns = [
        "Native.id", "HB.import_ref", "HB.asset_id", "HB.name", "HB.description", "HB.quantity",
        "HB.is_location", "HB.location", "Native.parent_ref", "HB.label",
        "HB.model_number", "HB.manufacturer", "HB.notes", "HB.purchase_from", "HB.purchase_price",
        "HB.purchase_time", "Native.category", "Native.weight_g", "Native.status",
    ]
    static func export(_ inventory: Inventory, records: [Gear]? = nil) -> String {
        let records = (records ?? inventory.gear.filter { !$0.trashed }).sorted { a, b in
            let aLocation = inventory.extras(a.id).isLocation
            let bLocation = inventory.extras(b.id).isLocation
            if aLocation != bLocation { return aLocation }
            return inventory.path(a.id).components(separatedBy: "/").count
                < inventory.path(b.id).components(separatedBy: "/").count
        }
        return CSV.encode(
            [columns]
                + records.map { gear in
                    let d = inventory.extras(gear.id)
                    let location =
                        d.isLocation ? d.parentID.map { inventory.path($0) } ?? "" : inventory.location(for: gear.id)
                    return [
                        gear.id.uuidString, d.importRef, String(d.assetID), gear.name, d.description,
                        String(gear.quantity),
                        String(d.isLocation), location,
                        d.parentID.map { inventory.extras($0).importRef } ?? "", gear.tags, gear.model, gear.brand,
                        gear.notes,
                        gear.purchaseFrom, String(gear.purchasePrice), gear.purchaseDate, gear.category,
                        String(gear.weight), gear.status,
                    ]
                })
    }
    static func merge(_ text: String, into existing: Inventory) throws -> Inventory {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let delimiter: Unicode.Scalar = firstLine.contains("\t") ? "\t" : ","
        let rows = try CSV.parse(text, delimiter: delimiter)
        guard let header = rows.first, header.contains("HB.name") || header.contains("名称") else {
            throw failure("缺少 HB.name 或名称列。")
        }
        var next = existing
        var pendingParents: [(UUID, String)] = []
        for (line, values) in rows.dropFirst().enumerated() {
            try mergeRow(
                CSVImportRow(header: header, row: values, line: line), into: &next, pendingParents: &pendingParents)
        }
        try resolveRelationships(in: &next, pendingParents: pendingParents)
        next.locations = next.places.map(\.name)
        for gear in next.items {
            for name in gear.tags.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
            where !name.isEmpty && !next.labels.contains(where: { $0.name == name }) {
                next.labels.append(GearTag(name: name))
            }
        }
        next.organizeOutdoorCategories()
        return next
    }
    private static func ensureLocation(_ path: String, in inventory: inout Inventory) -> UUID? {
        var parent: UUID?
        for name in path.components(separatedBy: "/").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({
            !$0.isEmpty
        }) {
            if let location = inventory.places.first(where: {
                $0.name == name && inventory.extras($0.id).parentID == parent
            }) {
                parent = location.id
            } else {
                var location = Gear()
                location.name = name
                location.category = "位置"
                var detail = GearExtras()
                detail.isLocation = true
                detail.parentID = parent
                detail.assetID = (inventory.details.values.map(\.assetID).max() ?? 0) + 1
                detail.importRef = location.id.uuidString
                inventory.gear.append(location)
                inventory.details[location.id.uuidString] = detail
                parent = location.id
            }
        }
        return parent
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NativeCSV", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func mergeRow(
        _ row: CSVImportRow, into next: inout Inventory, pendingParents: inout [(UUID, String)]
    ) throws {
        let name = row.value("HB.name", "名称").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw failure("第 \(row.line + 2) 行名称为空。") }
        let reference = row.value("HB.import_ref")
        let nativeID = UUID(uuidString: row.value("Native.id"))
        let previous = next.gear.first { gear in
            (!reference.isEmpty && next.extras(gear.id).importRef == reference)
                || (nativeID != nil && gear.id == nativeID)
        }
        var gear = previous ?? Gear()
        var detail = previous.map { next.extras($0.id) } ?? GearExtras()
        gear.id = previous?.id ?? nativeID ?? UUID()
        gear.name = name
        try populateGear(&gear, from: row)
        try populateDetails(&detail, gear: gear, reference: reference, from: row, in: next)
        next.details[gear.id.uuidString] = detail
        let location = row.value("HB.location", "存放位置")
        if !location.isEmpty {
            detail.parentID = ensureLocation(location, in: &next)
        } else {
            detail.parentID = nil
        }
        let parentRef = row.value("Native.parent_ref")
        if !parentRef.isEmpty { pendingParents.append((gear.id, parentRef)) }
        storeGear(gear, in: &next)
        next.details[gear.id.uuidString] = detail
    }
    private static func storeGear(_ gear: Gear, in next: inout Inventory) {
        if let index = next.gear.firstIndex(where: { $0.id == gear.id }) {
            next.gear[index] = gear
        } else {
            next.gear.append(gear)
        }
    }
    private static func populateGear(_ gear: inout Gear, from row: CSVImportRow) throws {
        gear.brand = row.value("HB.manufacturer", "品牌")
        gear.model = row.value("HB.model_number", "型号")
        gear.quantity = try row.number(row.value("HB.quantity", "数量"), fallback: 1)
        guard gear.quantity > 0 else { throw failure("第 \(row.line + 2) 行数量须大于 0。") }
        gear.weight = try row.number(row.value("Native.weight_g", "单件重量(g)"))
        gear.purchasePrice = try row.number(row.value("HB.purchase_price", "购买价格"))
        gear.purchaseFrom = row.value("HB.purchase_from", "购买渠道")
        gear.purchaseDate = row.value("HB.purchase_time", "购买日期")
        gear.notes = row.value("HB.notes", "备注")
        gear.tags = row.value("HB.label", "标签")
        let category = row.value("Native.category", "分类")
        if !category.isEmpty { gear.category = category }
        let status = row.value("Native.status", "状态")
        if !status.isEmpty { gear.status = status }
        gear.trashed = false
    }

    private static func populateDetails(
        _ detail: inout GearExtras, gear: Gear, reference: String, from row: CSVImportRow, in next: Inventory
    ) throws {
        detail.description = row.value("HB.description")
        detail.isLocation = try row.flag(row.value("HB.is_location"))
        let assetString = row.value("HB.asset_id").replacingOccurrences(of: "-", with: "")
        if !assetString.isEmpty {
            guard let asset = Int(assetString), asset > 0 else { throw failure("第 \(row.line + 2) 行资产编号无效。") }
            detail.assetID = asset
        } else if detail.assetID == 0 {
            detail.assetID = (next.details.values.map(\.assetID).max() ?? 0) + 1
        }
        detail.importRef = reference.isEmpty ? gear.id.uuidString : reference
    }

    private static func resolveRelationships(in next: inout Inventory, pendingParents: [(UUID, String)]) throws {
        for (id, parentRef) in pendingParents {
            guard let parent = next.gear.first(where: { next.extras($0.id).importRef == parentRef }) else {
                throw failure("父级导入标识不存在：" + parentRef)
            }
            var detail = next.extras(id)
            detail.parentID = parent.id
            next.details[id.uuidString] = detail
        }
        let assetIDs = next.details.values.map(\.assetID).filter { $0 > 0 }
        guard Set(assetIDs).count == assetIDs.count else { throw failure("资产编号重复，未修改任何记录。") }
        for record in next.gear {
            let detail = next.extras(record.id)
            if let parent = detail.parentID {
                guard parent != record.id, !next.descendants(of: record.id).contains(parent),
                    !detail.isLocation || next.extras(parent).isLocation
                else { throw failure("父子层级无效，未修改任何记录。") }
            }
        }
    }
}

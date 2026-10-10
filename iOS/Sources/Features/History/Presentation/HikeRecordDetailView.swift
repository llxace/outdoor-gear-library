import SwiftUI

struct HikeRecordDetailView: View {
    let record: [String: Any]
    private var gearRows: [HikeGearSnapshot] {
        (record["gear"] as? [[String: Any]] ?? []).compactMap(HikeGearSnapshot.init)
    }
    private var date: Date? {
        guard let seconds = (record["date"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
    private var totalWeight: Double {
        gearRows.reduce(0) { $0 + $1.gear.weight * $1.quantity }
    }

    var body: some View {
        List {
            Section("行程") {
                LabeledContent("路线", value: record["routeName"] as? String ?? "未记录")
                LabeledContent("日期", value: date?.formatted(date: .long, time: .omitted) ?? "未记录")
                LabeledContent("里程", value: record["distance"] as? String ?? "未记录")
                LabeledContent("装备重量", value: "\((totalWeight / 1000).formatted(.number.precision(.fractionLength(2)))) kg")
            }
            if let notes = record["notes"] as? String, !notes.isEmpty {
                Section("备注") { Text(notes).font(.body) }
            }
            Section("当次装备 · \(gearRows.count) 件") {
                ForEach(gearRows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.gear.name).font(.headline)
                            Text("\(row.gear.category) · \(row.gear.brand)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("×\(row.quantity.formatted())")
                            Text("\((row.gear.weight * row.quantity).formatted()) g").font(.caption).foregroundStyle(.secondary)
                        }.font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(OutdoorPalette.background)
        .navigationTitle(record["title"] as? String ?? "徒步记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HikeGearSnapshot: Identifiable {
    let id: UUID
    let gear: Gear
    let quantity: Double

    init?(_ raw: [String: Any]) {
        guard let gearRaw = raw["gear"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: gearRaw),
              let gear = try? JSONDecoder().decode(Gear.self, from: data) else { return nil }
        self.id = UUID(uuidString: raw["id"] as? String ?? "") ?? gear.id
        self.gear = gear
        self.quantity = raw["quantity"] as? Double ?? 1
    }
}

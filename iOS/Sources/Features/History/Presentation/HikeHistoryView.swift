import SwiftUI

struct HikeHistoryView: View {
    @EnvironmentObject private var library: GearLibrary
    private var records: [[String: Any]] { library.hikeHistory.sorted { timestamp($0) > timestamp($1) } }

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("还没有徒步记录", systemImage: "figure.hiking", description: Text("从 Mac 导入的历史记录会显示在这里。"))
            } else {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    NavigationLink { HikeRecordDetailView(record: record) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record["title"] as? String ?? record["routeName"] as? String ?? "徒步记录").font(.headline)
                            HStack {
                                Text(formattedDate(record["date"]))
                                Spacer()
                                Text(record["distance"] as? String ?? "")
                            }.font(.caption).foregroundStyle(.secondary)
                            if let notes = record["notes"] as? String, !notes.isEmpty {
                                Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            let count = (record["gear"] as? [[String: Any]] ?? []).count
                            Label("\(count) 件历史装备", systemImage: "backpack").font(.caption2).foregroundStyle(OutdoorPalette.accent)
                        }.padding(.vertical, 5)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(OutdoorPalette.background)
        .navigationTitle("徒步记录 · \(records.count)")
    }

    private func timestamp(_ record: [String: Any]) -> Double {
        (record["date"] as? NSNumber)?.doubleValue ?? 0
    }

    private func formattedDate(_ value: Any?) -> String {
        guard let seconds = (value as? NSNumber)?.doubleValue else { return "日期未记录" }
        return Date(timeIntervalSinceReferenceDate: seconds).formatted(date: .numeric, time: .omitted)
    }
}

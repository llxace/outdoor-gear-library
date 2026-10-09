import SwiftUI
import MapKit
import Charts

struct DepartureCalendar: View {
    @Binding var selection: Date
    @State private var month: Date
    private let calendar = Calendar.current
    private var earliestSelectableDate: Date { Self.earliestSelectableDate(from: Date(), calendar: calendar) }

    static func earliestSelectableDate(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .minute, for: now)?.end ?? now
    }

    init(selection: Binding<Date>) {
        _selection = selection
        _month = State(initialValue: selection.wrappedValue)
    }
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var offset: Int { calendar.component(.weekday, from: start) - 1 }
    private var count: Int { calendar.range(of: .day, in: .month, for: start)!.count }
    private var cells: Int { ((offset + count + 6) / 7) * 7 }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(start.formatted(.dateTime.year().month(.wide))).font(.headline)
                Spacer()
                Button {
                    move(-1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24)
                }.buttonStyle(.plain).disabled(!canMoveToPreviousMonth).accessibilityLabel("上个月")
                Button {
                    month = Date()
                    let today = Date()
                    let time = calendar.dateComponents([.hour, .minute], from: selection)
                    if let candidate = calendar.date(
                        bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: today
                    ) {
                        selection = max(candidate, earliestSelectableDate)
                    }
                } label: {
                    Text("今天").font(.caption)
                }.buttonStyle(.bordered).controlSize(.small)
                Button {
                    move(1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("下个月")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                ForEach(Array(["日", "一", "二", "三", "四", "五", "六"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption).foregroundStyle(.secondary).frame(height: 22)
                }
                ForEach(0..<cells, id: \.self) { cell in
                    let day = calendar.date(byAdding: .day, value: cell - offset, to: start)!
                    let selected = calendar.isDate(day, inSameDayAs: selection)
                    let currentMonth = calendar.isDate(day, equalTo: start, toGranularity: .month)
                    Button {
                        let time = calendar.dateComponents([.hour, .minute], from: selection)
                        if let date = calendar.date(
                            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
                        {
                            selection = max(date, earliestSelectableDate)
                            month = day
                        }
                    } label: {
                        Text(String(calendar.component(.day, from: day))).font(
                            .callout.weight(selected ? .semibold : .regular)
                        )
                        .foregroundColor(selected ? .white : (currentMonth ? .primary : .secondary.opacity(0.45)))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            if calendar.isDateInToday(day) {
                                Circle().fill(selected ? .white : Color.accentColor).frame(width: 3, height: 3).padding(
                                    .bottom, 3)
                            }
                        }
                    }.buttonStyle(.plain)
                        .disabled(calendar.startOfDay(for: day) < calendar.startOfDay(for: Date()))
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        .accessibilityValue(selected ? "已选" : "")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(Color.accentColor)
                Text("已选").foregroundStyle(.secondary)
                Text(selection.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .onAppear { month = selection }
        .padding(12).background(GearDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var canMoveToPreviousMonth: Bool {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: start),
              let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start else { return false }
        return previous >= currentMonth
    }
    private func move(_ value: Int) {
        if let date = calendar.date(byAdding: .month, value: value, to: start),
           value > 0 || date >= (calendar.dateInterval(of: .month, for: Date())?.start ?? Date()) {
            month = date
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct BorrowedGearPicker: View {
    @EnvironmentObject private var library: GearLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var candidates: [Gear] = []
    @State private var ownerName = "同行者"
    @State private var ownerID = UUID()
    @State private var selected: Set<UUID> = []
    @State private var quantities: [UUID: Double] = [:]
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("导入同行者装备", systemImage: "person.2.badge.plus")
                    } description: {
                        Text("选择另一份户外装备库 JSON，只会把勾选的装备加入本次打包，不会合并到你的装备库。")
                    } actions: {
                        Button("选择装备库文件") { importing = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            TextField("同行者名称", text: $ownerName)
                        }
                        Section("选择要携带的装备") {
                            ForEach(candidates) { gear in
                                HStack {
                                    Button {
                                        if selected.contains(gear.id) { selected.remove(gear.id) }
                                        else { selected.insert(gear.id) }
                                    } label: {
                                        Image(systemName: selected.contains(gear.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(gear.id) ? OutdoorPalette.accent : .secondary)
                                    }.buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(gear.name).font(.headline)
                                        Text("\(gear.category) · 库存 \(gear.quantity.formatted())")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Stepper(value: quantityBinding(for: gear), in: 1...max(1, gear.quantity), step: 1) {
                                        Text("\(quantityBinding(for: gear).wrappedValue.formatted()) 件").font(.caption)
                                    }.labelsHidden()
                                    Text("\(quantityBinding(for: gear).wrappedValue.formatted())")
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                        if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
                    }
                }
            }
            .navigationTitle("同行者装备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("加入打包") { addSelected() }.disabled(selected.isEmpty || ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case let .success(url): loadLibrary(from: url)
                case let .failure(error): message = error.localizedDescription
                }
            }
        }
    }

    private func quantityBinding(for gear: Gear) -> Binding<Double> {
        Binding(get: { quantities[gear.id] ?? 1 }, set: { quantities[gear.id] = $0 })
    }

    private func loadLibrary(from url: URL) {
        do {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            guard let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  let rows = raw["gear"] as? [[String: Any]],
                  let bytes = try? JSONSerialization.data(withJSONObject: rows) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            candidates = (try JSONDecoder().decode([Gear].self, from: bytes))
                .filter { !$0.trashed && $0.status != "损坏" && $0.quantity > 0 }
            let settings = raw["settings"] as? [String: Any] ?? [:]
            ownerName = settings["currentUserName"] as? String ?? url.deletingPathExtension().lastPathComponent
            ownerID = UUID()
            if candidates.isEmpty { message = "文件中没有可加入的装备。" }
        } catch {
            message = "无法读取这份装备库：\(error.localizedDescription)"
        }
    }

    private func addSelected() {
        for gear in candidates where selected.contains(gear.id) {
            library.addBorrowedGear(gear, ownerID: ownerID, ownerName: ownerName, quantity: quantities[gear.id] ?? 1)
        }
        dismiss()
    }
}

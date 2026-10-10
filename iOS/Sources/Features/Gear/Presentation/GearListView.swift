import SwiftUI
import UIKit

struct GearListView: View {
    @EnvironmentObject private var library: GearLibrary
    @State private var search = ""
    @State private var showingEditor = false
    @State private var editing: Gear?
    private var filtered: [Gear] {
        library.activeGear.filter { search.isEmpty || [$0.name, $0.brand, $0.model, $0.category].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { gear in
                    Button {
                        editing = gear
                        showingEditor = true
                    } label: { GearRow(gear: gear) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("打包", systemImage: "checkmark") { library.togglePacked(gear) }.tint(OutdoorPalette.accent)
                        Button("回收", systemImage: "trash") { library.moveToTrash(gear) }.tint(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OutdoorPalette.background)
            .searchable(text: $search, prompt: "搜索装备")
            .navigationTitle("装备库 · \(filtered.count)")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("添加", systemImage: "plus") { editing = nil; showingEditor = true } } }
            .sheet(isPresented: $showingEditor) { GearEditor(gear: editing ?? Gear()).environmentObject(library) }
        }
    }
}

struct GearRow: View {
    @EnvironmentObject private var library: GearLibrary
    let gear: Gear
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let name = gear.photo, let image = UIImage(contentsOfFile: library.photoURL(for: name).path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "backpack").font(.title3).foregroundStyle(OutdoorPalette.accent).frame(maxWidth: .infinity, maxHeight: .infinity).background(OutdoorPalette.accent.opacity(0.12))
                }
            }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(gear.name.isEmpty ? "未命名装备" : gear.name).font(.headline).foregroundStyle(.primary)
                Text([gear.category, gear.brand, gear.status].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if gear.weight > 0 { Text("\(gear.weight.formatted(.number.precision(.fractionLength(0...1)))) g").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }
}

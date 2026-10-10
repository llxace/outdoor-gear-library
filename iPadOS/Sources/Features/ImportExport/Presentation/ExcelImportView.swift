import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExcelImportView: View {
    @EnvironmentObject var store: GearStore
    @Environment(\.dismiss) private var dismiss
    let source: ExcelImportSource
    @State private var sheetID = ""
    @State private var rows: [[String]] = []
    @State private var headerRow = 0
    @State private var mapping: [String] = []
    @State private var update = true
    @State private var result: ExcelImportResult?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导入 Excel 装备表").font(.title2.bold())
            Text(source.workbook.url.lastPathComponent).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack {
                    sheetPicker.frame(maxWidth: 330)
                    headerRowStepper
                }
                VStack(alignment: .leading) {
                    sheetPicker
                    headerRowStepper
                }
            }
            Toggle("按装备 ID 更新已有记录；没有标识的行新增", isOn: $update)
            Text("仅导入对应的装备基本资料，其余列忽略。重量按克保存；购买价格是该记录的总价。图片及其他工作表的关联记录不会自动导入。")
                .font(.callout).foregroundStyle(.secondary)
            GeometryReader { area in
                if area.size.width < 720 {
                    VStack(spacing: 10) {
                        columnMapping.frame(height: area.size.height * 0.55)
                        importPreview
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        columnMapping
                        importPreview
                    }
                }
            }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认导入") { if let result, store.commitExcel(result) { dismiss() } }.keyboardShortcut(
                    .defaultAction
                ).disabled(result == nil)
            }
        }.padding(22).frame(maxWidth: 1100, maxHeight: .infinity)
            .onAppear {
                sheetID =
                    source.workbook.sheets.first(where: { $0.name.contains("主库") })?.id ?? source.workbook.sheets[0].id
                loadSheet()
            }
            .onChange(of: sheetID) { _, _ in loadSheet() }
            .onChange(of: headerRow) { _, _ in resetMapping() }
            .onChange(of: mapping) { _, _ in preview() }
            .onChange(of: update) { _, _ in preview() }
    }
    private var sheetPicker: some View {
        Picker("工作表", selection: $sheetID) { ForEach(source.workbook.sheets) { Text($0.name).tag($0.id) } }
    }
    private var headerRowStepper: some View {
        Stepper("表头在第 \(headerRow + 1) 行", value: $headerRow, in: 0...max(0, min(rows.count - 1, 29)))
    }
    private func loadSheet() {
        do {
            guard let sheet = source.workbook.sheets.first(where: { $0.id == sheetID }) else { return }
            rows = try source.workbook.rows(in: sheet)
            headerRow = ExcelImport.headerRow(rows)
            resetMapping()
        } catch {
            rows = []
            mapping = []
            result = nil
            message = error.localizedDescription
        }
    }
    private func resetMapping() {
        mapping = rows.indices.contains(headerRow) ? ExcelImport.mapping(rows[headerRow]) : []
        preview()
    }
    private func preview() {
        do {
            result = try ExcelImport.prepare(
                rows: rows, headerRow: headerRow, mapping: mapping, into: store.inventory, update: update)
            message = nil
        } catch {
            result = nil
            message = error.localizedDescription
        }
    }

    private var columnMapping: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(mapping.indices, id: \.self) { index in
                    HStack {
                        Text(rows[headerRow][index].isEmpty ? "空列 \(index + 1)" : rows[headerRow][index]).frame(
                            width: 170, alignment: .leading)
                        Picker("对应字段", selection: $mapping[index]) {
                            ForEach(ExcelImport.fields, id: \.self) { Text($0) }
                        }.labelsHidden().frame(width: 170)
                    }
                }
            }.padding(8)
        }.frame(maxWidth: .infinity)
    }

    private var importPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("导入预览").font(.headline)
                if let result {
                    Text("新增 \(result.added) 条 · 更新 \(result.updated) 条 · 跳过 \(result.skipped) 行")
                    ForEach(Array(result.names.prefix(10).enumerated()), id: \.offset) { entry in
                        Text("\(entry.offset + 1). \(entry.element)")
                    }
                    if result.names.count > 10 { Text("以及其他 \(result.names.count - 10) 条记录。") }
                    if !result.warnings.isEmpty {
                        Text("有 \(result.warnings.count) 项数字待确认，原文会保留为参数。").foregroundStyle(.orange)
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
}

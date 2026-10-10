import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExcelImportSource: Identifiable {
    let id = UUID()
    let workbook: ExcelWorkbook
}

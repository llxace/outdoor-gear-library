import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExcelImportSource: Identifiable {
    let id = UUID()
    let workbook: ExcelWorkbook
}

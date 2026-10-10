import Foundation

struct ExcelImportResult {
    let inventory: Inventory
    let names: [String]
    let added: Int
    let updated: Int
    let skipped: Int
    let warnings: [String]
}

import Foundation
import Observation

nonisolated struct ExportRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let format: String
    let cardCount: Int
    let exportType: String

    init(format: String, cardCount: Int, exportType: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.format = format
        self.cardCount = cardCount
        self.exportType = exportType
    }
}

@Observable
class ExportHistoryService {
    static let shared = ExportHistoryService()
    private let storageKey = "export_history_v1"

    var records: [ExportRecord] = []

    private init() {
        loadRecords()
    }

    func recordExport(format: String, cardCount: Int, exportType: String) {
        let record = ExportRecord(format: format, cardCount: cardCount, exportType: exportType)
        records.insert(record, at: 0)
        if records.count > 100 {
            records = Array(records.prefix(100))
        }
        saveRecords()
    }

    func clearHistory() {
        records.removeAll()
        saveRecords()
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([ExportRecord].self, from: data) else { return }
        records = loaded
    }
}

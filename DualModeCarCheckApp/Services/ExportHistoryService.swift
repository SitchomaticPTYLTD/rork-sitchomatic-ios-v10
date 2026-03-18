import Foundation
import Observation

@Observable
class ExportHistoryService {
    static let shared = ExportHistoryService()
    private init() {}
}

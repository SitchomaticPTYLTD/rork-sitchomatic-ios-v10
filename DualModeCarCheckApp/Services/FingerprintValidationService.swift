import Foundation
import Observation

@Observable
class FingerprintValidationService {
    static let shared = FingerprintValidationService()

    nonisolated struct FingerprintScore: Identifiable, Sendable {
        let id: UUID
        let score: Double
        let date: Date

        init(id: UUID = UUID(), score: Double = 0, date: Date = Date()) {
            self.id = id
            self.score = score
            self.date = date
        }
    }

    var formattedPassRate: String = "N/A"
    var averageScore: Double = 0
    var scoreHistory: [FingerprintScore] = []
    var lastScore: FingerprintScore?

    private init() {}
}

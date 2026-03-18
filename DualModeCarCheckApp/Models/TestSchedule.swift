import Foundation

nonisolated struct TestSchedule: Identifiable, Codable, Sendable {
    let id: UUID
    let scheduledDate: Date
    let cardFilter: CardFilter

    nonisolated enum CardFilter: String, Codable, CaseIterable, Sendable {
        case allUntested = "All Untested"
        case deadOnly = "Dead Only"
        case allNonWorking = "All Non-Working"
    }

    init(id: UUID = UUID(), scheduledDate: Date, cardFilter: CardFilter) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.cardFilter = cardFilter
    }
}

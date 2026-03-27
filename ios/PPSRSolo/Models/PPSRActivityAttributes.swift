import ActivityKit
import Foundation

nonisolated struct PPSRActivityAttributes: ActivityAttributes {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        var totalCards: Int
        var completedCards: Int
        var workingCount: Int
        var deadCount: Int
        var requeuedCount: Int
        var elapsedSeconds: Int
        var estimatedSecondsRemaining: Int
        var cardsPerMinute: Double
        var isFinished: Bool
        var wasStopped: Bool
    }

    var batchId: String
    var startedAt: Date
}

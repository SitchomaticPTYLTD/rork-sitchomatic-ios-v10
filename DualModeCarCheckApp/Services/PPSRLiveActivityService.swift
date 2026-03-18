import ActivityKit
import Foundation

@MainActor
class PPSRLiveActivityService {
    static let shared = PPSRLiveActivityService()

    private var currentActivity: Activity<PPSRActivityAttributes>?

    var isActivityActive: Bool {
        currentActivity != nil
    }

    func startBatchActivity(totalCards: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        endCurrentActivity()

        let attributes = PPSRActivityAttributes(
            batchId: UUID().uuidString,
            startedAt: Date()
        )

        let initialState = PPSRActivityAttributes.ContentState(
            totalCards: totalCards,
            completedCards: 0,
            workingCount: 0,
            deadCount: 0,
            requeuedCount: 0,
            elapsedSeconds: 0,
            estimatedSecondsRemaining: 0,
            cardsPerMinute: 0,
            isFinished: false,
            wasStopped: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            // silently fail
        }
    }

    func updateActivity(
        totalCards: Int,
        completedCards: Int,
        working: Int,
        dead: Int,
        requeued: Int,
        elapsedSeconds: Int,
        estimatedRemaining: Int,
        cardsPerMinute: Double
    ) {
        guard let activity = currentActivity else { return }

        let state = PPSRActivityAttributes.ContentState(
            totalCards: totalCards,
            completedCards: completedCards,
            workingCount: working,
            deadCount: dead,
            requeuedCount: requeued,
            elapsedSeconds: elapsedSeconds,
            estimatedSecondsRemaining: estimatedRemaining,
            cardsPerMinute: cardsPerMinute,
            isFinished: false,
            wasStopped: false
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity(working: Int, dead: Int, requeued: Int, totalCards: Int, elapsed: Int, wasStopped: Bool) {
        guard let activity = currentActivity else { return }

        let finalState = PPSRActivityAttributes.ContentState(
            totalCards: totalCards,
            completedCards: working + dead + requeued,
            workingCount: working,
            deadCount: dead,
            requeuedCount: requeued,
            elapsedSeconds: elapsed,
            estimatedSecondsRemaining: 0,
            cardsPerMinute: 0,
            isFinished: true,
            wasStopped: wasStopped
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(120)))
            self.currentActivity = nil
        }
    }

    func endCurrentActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}

import Foundation

nonisolated struct BatchPreset: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let maxConcurrency: Int
    let stealthEnabled: Bool
    let useEmailRotation: Bool
    let retrySubmitOnFail: Bool
    let testTimeout: TimeInterval

    init(
        id: UUID = UUID(),
        name: String,
        maxConcurrency: Int,
        stealthEnabled: Bool,
        useEmailRotation: Bool,
        retrySubmitOnFail: Bool,
        testTimeout: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.maxConcurrency = maxConcurrency
        self.stealthEnabled = stealthEnabled
        self.useEmailRotation = useEmailRotation
        self.retrySubmitOnFail = retrySubmitOnFail
        self.testTimeout = testTimeout
    }
}

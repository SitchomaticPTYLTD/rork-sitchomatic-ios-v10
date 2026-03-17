import Foundation

@MainActor
class DefaultSettingsService {
    static let shared = DefaultSettingsService()
    private let appliedKey = "default_settings_applied_v2"

    var hasAppliedDefaults: Bool {
        UserDefaults.standard.bool(forKey: appliedKey)
    }

    func applyDefaultsIfNeeded() {
        guard !hasAppliedDefaults else { return }

        let proxyService = ProxyRotationService.shared
        proxyService.setConnectionMode(.dns, for: .ppsr)

        UserDefaults.standard.set(true, forKey: appliedKey)
    }
}

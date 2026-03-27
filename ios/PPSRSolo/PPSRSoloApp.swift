import SwiftUI
import UIKit

@main
struct PPSRSoloApp: App {
    @AppStorage("activeAppMode") private var activeModeRaw: String = ""

    @State private var nordInitialized: Bool = false

    private var activeMode: ActiveAppMode? {
        ActiveAppMode(rawValue: activeModeRaw)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let mode = activeMode {
                    Group {
                        switch mode {
                        case .ppsr:
                            ContentView()
                        case .debugLog:
                            NavigationStack {
                                DebugLogView()
                            }
                            .withMainMenuButton()
                            .preferredColorScheme(.dark)
                        case .nordConfig:
                            NordLynxConfigView()
                        case .vault:
                            NavigationStack {
                                StorageFileBrowserView()
                            }
                            .withMainMenuButton()
                            .preferredColorScheme(.dark)
                        case .ipScoreTest:
                            IPScoreTestView()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                } else {
                    MainMenuView(activeMode: Binding(
                        get: { activeMode },
                        set: { newMode in
                            if let m = newMode {
                                activeModeRaw = m.rawValue
                            } else {
                                activeModeRaw = ""
                            }
                        }
                    ))
                    .transition(.opacity)
                }
            }
            .task {
                if !nordInitialized {
                    nordInitialized = true
                    let vault = PersistentFileStorageService.shared
                    let didRestore = vault.restoreIfNeeded()
                    if didRestore {
                        DebugLogger.shared.log("App launched — restored state from vault", category: .persistence, level: .success)
                    }
                    DefaultSettingsService.shared.applyDefaultsIfNeeded()
                    let nord = NordVPNService.shared
                    if !nord.hasAccessKey {
                        nord.setAccessKey(NordVPNKeyStore.defaultNickKey)
                    }
                    if nord.isTokenExpired {
                        nord.lastError = "NordVPN access token needs to be refreshed before fetching a private key."
                    }
                    vault.saveFullState()
                    performAutoCleanup()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                PersistentFileStorageService.shared.forceSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                PersistentFileStorageService.shared.forceSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                WebViewPool.shared.drainAll()
                DebugLogger.shared.log("Memory warning — drained WebView pool", category: .system, level: .warning)
            }
        }
    }

    private func performAutoCleanup() {
        let logger = DebugLogger.shared

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let beforeCount = logger.entryCount
        logger.trimEntries(olderThan: sevenDaysAgo)
        let trimmed = beforeCount - logger.entryCount
        if trimmed > 0 {
            logger.log("Auto-cleanup: removed \(trimmed) debug log entries older than 7 days", category: .system, level: .info)
        }

        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        ScreenshotCacheService.shared.purgeStaleScreenshots(olderThan: threeDaysAgo, keepOverrides: [])
    }
}

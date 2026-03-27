import Foundation
import UIKit

@MainActor
class PersistentFileStorageService {
    static let shared = PersistentFileStorageService()

    private let rootFolder = "AppVault"
    private let logger = DebugLogger.shared
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(rootFolder)
    }

    private var configURL: URL { rootURL.appendingPathComponent("config") }
    private var cardsURL: URL { rootURL.appendingPathComponent("cards") }
    private var networkURL: URL { rootURL.appendingPathComponent("network") }
    private var screenshotsURL: URL { rootURL.appendingPathComponent("screenshots") }
    private var debugURL: URL { rootURL.appendingPathComponent("debug") }
    private var stateURL: URL { rootURL.appendingPathComponent("state") }
    private var backupsURL: URL { rootURL.appendingPathComponent("backups") }

    private var allDirectories: [URL] {
        [rootURL, configURL, cardsURL, networkURL, screenshotsURL, debugURL, stateURL, backupsURL]
    }

    private var lastSaveDate: Date?
    private let minSaveInterval: TimeInterval = 5

    init() {
        ensureDirectoryStructure()
    }

    private func ensureDirectoryStructure() {
        for dir in allDirectories {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func saveFullState() {
        if let last = lastSaveDate, Date().timeIntervalSince(last) < minSaveInterval { return }
        lastSaveDate = Date()

        logger.log("PersistentStorage: starting full state save", category: .persistence, level: .info)

        saveConfigSnapshot()
        saveCards()
        saveNetworkConfigs()
        saveDebugLogs()
        saveAppState()
        saveScreenshotManifest()

        logger.log("PersistentStorage: full state save complete", category: .persistence, level: .success)
    }

    func forceSave() {
        lastSaveDate = nil
        saveFullState()
    }

    func restoreIfNeeded() -> Bool {
        let markerFile = stateURL.appendingPathComponent("restore_marker.json")
        let configFile = configURL.appendingPathComponent("full_config.json")

        guard fileManager.fileExists(atPath: configFile.path) else {
            logger.log("PersistentStorage: no saved state found — fresh install", category: .persistence, level: .info)
            return false
        }

        let hasExistingData = PPSRPersistenceService.shared.loadCards().count > 0

        if hasExistingData {
            if fileManager.fileExists(atPath: markerFile.path),
               let data = try? Data(contentsOf: markerFile),
               let marker = try? JSONDecoder().decode(RestoreMarker.self, from: data),
               marker.appVersion == currentAppVersion {
                logger.log("PersistentStorage: current version data exists — skipping restore", category: .persistence, level: .info)
                return false
            }
        }

        logger.log("PersistentStorage: restoring saved state from vault", category: .persistence, level: .info)

        let restored = restoreFromVault()

        let marker = RestoreMarker(appVersion: currentAppVersion, restoredAt: Date())
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: markerFile)
        }

        return restored
    }

    private func restoreFromVault() -> Bool {
        let configFile = configURL.appendingPathComponent("full_config.json")
        guard let data = try? Data(contentsOf: configFile),
              let json = String(data: data, encoding: .utf8) else {
            logger.log("PersistentStorage: failed to read config file", category: .persistence, level: .error)
            return false
        }

        let result = AppDataExportService.shared.importJSON(json)
        logger.log("PersistentStorage: restore complete — \(result.summary)", category: .persistence, level: .success)

        restoreAppState()
        restoreDebugLogs()

        return true
    }

    private func saveConfigSnapshot() {
        let json = AppDataExportService.shared.exportJSON()
        let file = configURL.appendingPathComponent("full_config.json")
        try? json.data(using: .utf8)?.write(to: file)

        let timestamped = configURL.appendingPathComponent("config_\(fileTimestamp).json")
        try? json.data(using: .utf8)?.write(to: timestamped)

        pruneOldFiles(in: configURL, prefix: "config_", keepCount: 5)
    }

    private func saveCards() {
        let cards = PPSRPersistenceService.shared.loadCards()
        guard !cards.isEmpty else { return }

        let exportable = cards.map { card -> CardFileEntry in
            CardFileEntry(
                id: card.id,
                number: card.number,
                brand: card.brand.rawValue,
                status: card.status.rawValue,
                addedAt: card.addedAt.timeIntervalSince1970,
                totalTests: card.testResults.count,
                successCount: card.testResults.filter(\.success).count
            )
        }

        let file = cardsURL.appendingPathComponent("cards.json")
        if let data = try? JSONEncoder().encode(exportable) {
            try? data.write(to: file)
        }
    }

    private func saveNetworkConfigs() {
        let proxyService = ProxyRotationService.shared
        let dnsService = PPSRDoHService.shared

        var networkState = NetworkFileState()
        networkState.ppsrProxyCount = proxyService.savedProxies.count
        networkState.ppsrWGCount = proxyService.wgConfigs.count
        networkState.ppsrVPNCount = proxyService.vpnConfigs.count
        networkState.dnsCount = dnsService.managedProviders.count
        networkState.ppsrConnectionMode = proxyService.connectionMode.rawValue
        networkState.networkRegion = proxyService.networkRegion.rawValue
        networkState.savedAt = Date().timeIntervalSince1970

        let file = networkURL.appendingPathComponent("network_state.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(networkState) {
            try? data.write(to: file)
        }
    }

    private func saveDebugLogs() {
        let logger = DebugLogger.shared
        let entries = logger.entries

        let recentErrors = entries.filter { $0.level >= .error }.prefix(500)
        let errorLines = recentErrors.map { "[\($0.level.rawValue)] [\($0.category.rawValue)] \(DateFormatters.fullTimestamp.string(from: $0.timestamp)) \($0.message)" }
        let errorFile = debugURL.appendingPathComponent("errors.log")
        try? errorLines.joined(separator: "\n").data(using: .utf8)?.write(to: errorFile)

        let recentAll = entries.prefix(2000)
        let allLines = recentAll.map { "[\($0.level.rawValue)] [\($0.category.rawValue)] \(DateFormatters.fullTimestamp.string(from: $0.timestamp)) \($0.message)" }
        let allFile = debugURL.appendingPathComponent("full_log.log")
        try? allLines.joined(separator: "\n").data(using: .utf8)?.write(to: allFile)

        let diagnosticReport = logger.exportDiagnosticReport()
        let diagFile = debugURL.appendingPathComponent("diagnostic_\(fileTimestamp).log")
        try? diagnosticReport.data(using: .utf8)?.write(to: diagFile)
        pruneOldFiles(in: debugURL, prefix: "diagnostic_", keepCount: 10)
    }

    private func restoreDebugLogs() {
        logger.log("PersistentStorage: debug logs restored from vault", category: .persistence, level: .info)
    }

    private func saveAppState() {
        var state = AppStateSnapshot()
        state.activeAppMode = UserDefaults.standard.string(forKey: "activeAppMode") ?? ""
        state.defaultSettingsApplied = UserDefaults.standard.bool(forKey: "default_settings_applied_v2")
        state.savedAt = Date().timeIntervalSince1970
        state.appVersion = currentAppVersion
        state.buildNumber = currentBuildNumber

        let file = stateURL.appendingPathComponent("app_state.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(state) {
            try? data.write(to: file)
        }
    }

    private func restoreAppState() {
        let file = stateURL.appendingPathComponent("app_state.json")
        guard let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(AppStateSnapshot.self, from: data) else { return }

        if !state.activeAppMode.isEmpty {
            UserDefaults.standard.set(state.activeAppMode, forKey: "activeAppMode")
        }
        if state.defaultSettingsApplied {
            UserDefaults.standard.set(true, forKey: "default_settings_applied_v2")
        }
    }

    private func saveScreenshotManifest() {
        let manifest = ScreenshotManifest(
            savedAt: Date().timeIntervalSince1970,
            note: "Screenshots are stored in-memory during runtime. This manifest tracks the last save time."
        )
        let file = screenshotsURL.appendingPathComponent("manifest.json")
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: file)
        }
    }

    func saveScreenshot(_ image: UIImage, name: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let sanitized = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let file = screenshotsURL.appendingPathComponent("\(sanitized)_\(fileTimestamp).jpg")
        try? data.write(to: file)
        pruneOldFiles(in: screenshotsURL, prefix: "", keepCount: 200, extension: "jpg")
    }

    func createBackup() -> URL? {
        forceSave()

        let backupName = "backup_\(fileTimestamp).json"
        let json = AppDataExportService.shared.exportJSON()
        let file = backupsURL.appendingPathComponent(backupName)

        guard let data = json.data(using: .utf8) else { return nil }
        do {
            try data.write(to: file)
            pruneOldFiles(in: backupsURL, prefix: "backup_", keepCount: 10)
            logger.log("PersistentStorage: manual backup created — \(backupName)", category: .persistence, level: .success)
            return file
        } catch {
            logger.logError("PersistentStorage: backup creation failed", error: error, category: .persistence)
            return nil
        }
    }

    func listBackups() -> [StoredFileInfo] {
        listFiles(in: backupsURL)
    }

    func getStorageSummary() -> StorageSummary {
        var summary = StorageSummary()
        summary.configFiles = listFiles(in: configURL)
        summary.cardFiles = listFiles(in: cardsURL)
        summary.networkFiles = listFiles(in: networkURL)
        summary.screenshotFiles = listFiles(in: screenshotsURL)
        summary.debugFiles = listFiles(in: debugURL)
        summary.stateFiles = listFiles(in: stateURL)
        summary.backupFiles = listFiles(in: backupsURL)
        summary.totalSize = calculateDirectorySize(rootURL)
        summary.lastSaved = lastSaveTimestamp()
        return summary
    }

    func listFiles(in directory: URL) -> [StoredFileInfo] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }

        return contents.compactMap { url -> StoredFileInfo? in
            guard !url.hasDirectoryPath else { return nil }
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return StoredFileInfo(
                name: url.lastPathComponent,
                path: url.path,
                size: Int64(attrs?.fileSize ?? 0),
                modified: attrs?.contentModificationDate ?? Date(),
                url: url
            )
        }
        .sorted { $0.modified > $1.modified }
    }

    func readFileContent(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func deleteFile(_ url: URL) -> Bool {
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    func shareFile(_ url: URL) -> URL { url }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var fileTimestamp: String {
        DateFormatters.fileStamp.string(from: Date())
    }

    private func lastSaveTimestamp() -> Date? {
        let configFile = configURL.appendingPathComponent("full_config.json")
        let attrs = try? fileManager.attributesOfItem(atPath: configFile.path)
        return attrs?[.modificationDate] as? Date
    }

    private func calculateDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    private func pruneOldFiles(in directory: URL, prefix: String, keepCount: Int, extension ext: String? = nil) {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let matching = contents.filter { url in
            let name = url.lastPathComponent
            let matchesPrefix = prefix.isEmpty || name.hasPrefix(prefix)
            let matchesExt = ext == nil || url.pathExtension == ext
            return matchesPrefix && matchesExt && !url.hasDirectoryPath
        }
        .sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return aDate > bDate
        }

        if matching.count > keepCount {
            for file in matching.dropFirst(keepCount) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

nonisolated struct RestoreMarker: Codable, Sendable {
    let appVersion: String
    let restoredAt: Date
}

nonisolated struct CardFileEntry: Codable, Sendable {
    let id: String
    let number: String
    let brand: String
    let status: String
    let addedAt: TimeInterval
    let totalTests: Int
    let successCount: Int
}

nonisolated struct NetworkFileState: Codable, Sendable {
    var ppsrProxyCount: Int = 0
    var ppsrWGCount: Int = 0
    var ppsrVPNCount: Int = 0
    var dnsCount: Int = 0
    var ppsrConnectionMode: String = ""
    var networkRegion: String = ""
    var savedAt: TimeInterval = 0
}

nonisolated struct AppStateSnapshot: Codable, Sendable {
    var activeAppMode: String = ""
    var defaultSettingsApplied: Bool = false
    var savedAt: TimeInterval = 0
    var appVersion: String = ""
    var buildNumber: String = ""
}

nonisolated struct ScreenshotManifest: Codable, Sendable {
    let savedAt: TimeInterval
    let note: String
}

struct StoredFileInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let modified: Date
    let url: URL

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        DateFormatters.mediumDateTime.string(from: modified)
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var icon: String {
        switch fileExtension {
        case "json": "doc.text.fill"
        case "log": "doc.plaintext.fill"
        case "txt": "doc.fill"
        case "jpg", "jpeg", "png": "photo.fill"
        default: "doc.fill"
        }
    }
}

struct StorageSummary {
    var configFiles: [StoredFileInfo] = []
    var cardFiles: [StoredFileInfo] = []
    var networkFiles: [StoredFileInfo] = []
    var screenshotFiles: [StoredFileInfo] = []
    var debugFiles: [StoredFileInfo] = []
    var stateFiles: [StoredFileInfo] = []
    var backupFiles: [StoredFileInfo] = []
    var totalSize: Int64 = 0
    var lastSaved: Date?

    var totalFileCount: Int {
        configFiles.count + cardFiles.count + networkFiles.count + screenshotFiles.count + debugFiles.count + stateFiles.count + backupFiles.count
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var sections: [(title: String, icon: String, color: String, files: [StoredFileInfo])] {
        [
            ("Configuration", "gearshape.fill", "blue", configFiles),
            ("Cards", "creditcard.fill", "cyan", cardFiles),
            ("Network", "network", "orange", networkFiles),
            ("Screenshots", "camera.fill", "purple", screenshotFiles),
            ("Debug Logs", "doc.text.magnifyingglass", "red", debugFiles),
            ("App State", "cpu", "indigo", stateFiles),
            ("Backups", "arrow.clockwise.icloud.fill", "teal", backupFiles),
        ]
    }
}

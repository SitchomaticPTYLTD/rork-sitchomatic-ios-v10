import Foundation
import CoreGraphics

nonisolated struct ComprehensiveExportConfig: Codable, Sendable {
    var version: String = "2.0"
    var exportedAt: String = ""

    var ppsrProxies: [ExportProxy] = []
    var ppsrVPNConfigs: [ExportVPN] = []
    var ppsrWGConfigs: [ExportWG] = []
    var dnsServers: [ExportDNS] = []
    var connectionModes: ExportConnectionModes = ExportConnectionModes()
    var networkRegion: String = "USA"
    var unifiedConnectionMode: String = "DNS"
    var settings: ExportSettings = ExportSettings()

    var ppsrCards: [ExportCard] = []
    var ppsrAppSettings: ExportPPSRAppSettings?
    var emailRotationList: [String] = []
    var cardSortOption: String?
    var cardSortAscending: Bool?
    var ppsrCropRect: ExportRect?
    var nordVPNAccessKey: String?
    var nordVPNPrivateKey: String?

    nonisolated struct ExportProxy: Codable, Sendable {
        let host: String
        let port: Int
        let username: String?
        let password: String?
    }

    nonisolated struct ExportVPN: Codable, Sendable {
        let fileName: String
        let remoteHost: String
        let remotePort: Int
        let proto: String
        let rawContent: String
        let enabled: Bool
    }

    nonisolated struct ExportWG: Codable, Sendable {
        let fileName: String
        let rawContent: String
        let enabled: Bool
    }

    nonisolated struct ExportDNS: Codable, Sendable {
        let name: String
        let url: String
        let enabled: Bool
    }

    nonisolated struct ExportConnectionModes: Codable, Sendable {
        var ppsr: String = "DNS"
    }

    nonisolated struct ExportSettings: Codable, Sendable {
        var placeholder: Bool = true
    }

    nonisolated struct ExportCard: Codable, Sendable {
        let id: String
        let number: String
        let expiryMonth: String
        let expiryYear: String
        let cvv: String
        let brand: String
        let status: String
        let addedAt: TimeInterval
        let testResults: [ExportCardTestResult]
        let binData: ExportBINData?
    }

    nonisolated struct ExportCardTestResult: Codable, Sendable {
        let timestamp: TimeInterval
        let success: Bool
        let vin: String
        let duration: TimeInterval
        let errorMessage: String?
    }

    nonisolated struct ExportBINData: Codable, Sendable {
        let bin: String
        let scheme: String
        let type: String
        let category: String
        let issuer: String
        let country: String
        let countryCode: String
        let isLoaded: Bool
    }

    nonisolated struct ExportPPSRAppSettings: Codable, Sendable {
        var email: String
        var maxConcurrency: Int
        var debugMode: Bool
        var appearanceMode: String
        var useEmailRotation: Bool
        var stealthEnabled: Bool
        var retrySubmitOnFail: Bool
        var cropRect: ExportRect?
    }

    nonisolated struct ExportRect: Codable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
}

typealias ExportableConfig = ComprehensiveExportConfig

@MainActor
class AppDataExportService {
    static let shared = AppDataExportService()

    func exportJSON() -> String {
        let proxyService = ProxyRotationService.shared
        let dnsService = PPSRDoHService.shared
        let emailService = PPSREmailRotationService.shared

        var config = ComprehensiveExportConfig()
        config.exportedAt = DateFormatters.exportTimestamp.string(from: Date())

        config.ppsrProxies = proxyService.savedProxies.map { .init(host: $0.host, port: $0.port, username: $0.username, password: $0.password) }
        config.ppsrVPNConfigs = proxyService.vpnConfigs.map { .init(fileName: $0.fileName, remoteHost: $0.remoteHost, remotePort: $0.remotePort, proto: $0.proto, rawContent: $0.rawContent, enabled: $0.isEnabled) }
        config.ppsrWGConfigs = proxyService.wgConfigs.map { .init(fileName: $0.fileName, rawContent: $0.rawContent, enabled: $0.isEnabled) }

        config.dnsServers = dnsService.managedProviders.map { .init(name: $0.name, url: $0.url, enabled: $0.isEnabled) }

        config.connectionModes = .init(ppsr: proxyService.connectionMode.rawValue)
        config.networkRegion = proxyService.networkRegion.rawValue
        config.unifiedConnectionMode = proxyService.unifiedConnectionMode.rawValue

        let ppsrCards = PPSRPersistenceService.shared.loadCards()
        config.ppsrCards = ppsrCards.map { card in
            .init(
                id: card.id,
                number: card.number,
                expiryMonth: card.expiryMonth,
                expiryYear: card.expiryYear,
                cvv: card.cvv,
                brand: card.brand.rawValue,
                status: card.status.rawValue,
                addedAt: card.addedAt.timeIntervalSince1970,
                testResults: card.testResults.map { r in
                    .init(timestamp: r.timestamp.timeIntervalSince1970, success: r.success, vin: r.vin, duration: r.duration, errorMessage: r.errorMessage)
                },
                binData: card.binData.map { b in
                    .init(bin: b.bin, scheme: b.scheme, type: b.type, category: b.category, issuer: b.issuer, country: b.country, countryCode: b.countryCode, isLoaded: b.isLoaded)
                }
            )
        }

        if let ppsrSettings = PPSRPersistenceService.shared.loadSettings() {
            var cropExport: ComprehensiveExportConfig.ExportRect?
            if let crop = ppsrSettings.screenshotCropRect, crop != .zero {
                cropExport = .init(x: crop.origin.x, y: crop.origin.y, width: crop.size.width, height: crop.size.height)
            }
            config.ppsrAppSettings = .init(
                email: ppsrSettings.email,
                maxConcurrency: ppsrSettings.maxConcurrency,
                debugMode: ppsrSettings.debugMode,
                appearanceMode: ppsrSettings.appearanceMode,
                useEmailRotation: ppsrSettings.useEmailRotation,
                stealthEnabled: ppsrSettings.stealthEnabled,
                retrySubmitOnFail: ppsrSettings.retrySubmitOnFail,
                cropRect: cropExport
            )
        }

        config.emailRotationList = emailService.emails

        if let sortRaw = UserDefaults.standard.string(forKey: "ppsr_card_sort_option") {
            config.cardSortOption = sortRaw
        }
        config.cardSortAscending = UserDefaults.standard.bool(forKey: "ppsr_card_sort_ascending")

        let nord = NordVPNService.shared
        if !nord.accessKey.isEmpty {
            config.nordVPNAccessKey = nord.accessKey
        }
        if !nord.privateKey.isEmpty {
            config.nordVPNPrivateKey = nord.privateKey
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    struct ImportResult {
        var proxiesImported: Int = 0
        var vpnImported: Int = 0
        var wgImported: Int = 0
        var dnsImported: Int = 0
        var cardsImported: Int = 0
        var emailsImported: Int = 0
        var ppsrSettingsImported: Bool = false
        var nordKeysImported: Bool = false
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if proxiesImported > 0 { parts.append("\(proxiesImported) proxies") }
            if vpnImported > 0 { parts.append("\(vpnImported) VPN configs") }
            if wgImported > 0 { parts.append("\(wgImported) WireGuard configs") }
            if dnsImported > 0 { parts.append("\(dnsImported) DNS servers") }
            if cardsImported > 0 { parts.append("\(cardsImported) PPSR cards") }
            if emailsImported > 0 { parts.append("\(emailsImported) emails") }
            if ppsrSettingsImported { parts.append("PPSR app settings") }
            if nordKeysImported { parts.append("NordVPN keys") }
            if parts.isEmpty { return "Nothing imported" }
            return "Imported: " + parts.joined(separator: ", ")
        }
    }

    func importJSON(_ jsonString: String) -> ImportResult {
        var result = ImportResult()

        guard let data = jsonString.data(using: .utf8) else {
            result.errors.append("Invalid text data")
            return result
        }

        let config: ComprehensiveExportConfig
        do {
            config = try JSONDecoder().decode(ComprehensiveExportConfig.self, from: data)
        } catch {
            result.errors.append("JSON parse error: \(error.localizedDescription)")
            return result
        }

        let proxyService = ProxyRotationService.shared
        let dnsService = PPSRDoHService.shared

        for ep in config.ppsrProxies {
            let line = formatProxyLine(ep)
            let report = proxyService.bulkImportSOCKS5(line)
            result.proxiesImported += report.added
        }

        for ev in config.ppsrVPNConfigs {
            if let vpn = OpenVPNConfig.parse(fileName: ev.fileName, content: ev.rawContent) {
                proxyService.importVPNConfig(vpn)
                if !ev.enabled { proxyService.toggleVPNConfig(vpn, enabled: false) }
                result.vpnImported += 1
            }
        }

        for ew in config.ppsrWGConfigs {
            if let wg = WireGuardConfig.parse(fileName: ew.fileName, content: ew.rawContent) {
                proxyService.importWGConfig(wg)
                if !ew.enabled { proxyService.toggleWGConfig(wg, enabled: false) }
                result.wgImported += 1
            }
        }

        for ed in config.dnsServers {
            if dnsService.addProvider(name: ed.name, url: ed.url) {
                if !ed.enabled {
                    if let found = dnsService.managedProviders.first(where: { $0.url == ed.url }) {
                        dnsService.toggleProvider(id: found.id, enabled: false)
                    }
                }
                result.dnsImported += 1
            }
        }

        if let ppsrMode = ConnectionMode(rawValue: config.connectionModes.ppsr) {
            proxyService.connectionMode = ppsrMode
        }

        if let region = NetworkRegion(rawValue: config.networkRegion) {
            proxyService.networkRegion = region
        }
        if let unified = ConnectionMode(rawValue: config.unifiedConnectionMode) {
            proxyService.setUnifiedConnectionMode(unified)
        }

        if !config.ppsrCards.isEmpty {
            let existingCards = PPSRPersistenceService.shared.loadCards()
            let existingNums = Set(existingCards.map(\.number))
            var merged = existingCards
            for ec in config.ppsrCards {
                guard !existingNums.contains(ec.number) else { continue }
                let card = PPSRCard(number: ec.number, expiryMonth: ec.expiryMonth, expiryYear: ec.expiryYear, cvv: ec.cvv)
                card.overrideId(ec.id)
                card.overrideAddedAt(Date(timeIntervalSince1970: ec.addedAt))
                if let status = CardStatus(rawValue: ec.status) { card.status = status }
                card.testResults = ec.testResults.map { r in
                    PPSRTestResult(success: r.success, vin: r.vin, duration: r.duration, errorMessage: r.errorMessage, timestamp: Date(timeIntervalSince1970: r.timestamp))
                }
                if let bin = ec.binData {
                    card.binData = PPSRBINData(bin: bin.bin, scheme: bin.scheme, type: bin.type, category: bin.category, issuer: bin.issuer, country: bin.country, countryCode: bin.countryCode, isLoaded: bin.isLoaded)
                }
                merged.append(card)
                result.cardsImported += 1
            }
            if result.cardsImported > 0 {
                PPSRPersistenceService.shared.saveCards(merged)
            }
        }

        if let ppsrSettings = config.ppsrAppSettings {
            var cropRect: CGRect = .zero
            if let cr = ppsrSettings.cropRect {
                cropRect = CGRect(x: cr.x, y: cr.y, width: cr.width, height: cr.height)
            }
            PPSRPersistenceService.shared.saveSettings(
                email: ppsrSettings.email,
                maxConcurrency: ppsrSettings.maxConcurrency,
                debugMode: ppsrSettings.debugMode,
                appearanceMode: ppsrSettings.appearanceMode,
                useEmailRotation: ppsrSettings.useEmailRotation,
                stealthEnabled: ppsrSettings.stealthEnabled,
                retrySubmitOnFail: ppsrSettings.retrySubmitOnFail,
                screenshotCropRect: cropRect
            )
            result.ppsrSettingsImported = true
        }

        if !config.emailRotationList.isEmpty {
            let emailService = PPSREmailRotationService.shared
            let existingSet = Set(emailService.emails)
            var added = 0
            for email in config.emailRotationList where !existingSet.contains(email) {
                emailService.emails.append(email)
                added += 1
            }
            result.emailsImported = added
        }

        if let sortOption = config.cardSortOption {
            UserDefaults.standard.set(sortOption, forKey: "ppsr_card_sort_option")
        }
        if let sortAsc = config.cardSortAscending {
            UserDefaults.standard.set(sortAsc, forKey: "ppsr_card_sort_ascending")
        }

        let nord = NordVPNService.shared
        if let accessKey = config.nordVPNAccessKey, !accessKey.isEmpty {
            nord.setAccessKey(accessKey)
            result.nordKeysImported = true
        }
        if let privateKey = config.nordVPNPrivateKey, !privateKey.isEmpty {
            nord.setPrivateKey(privateKey)
            result.nordKeysImported = true
        }

        return result
    }

    private func formatProxyLine(_ ep: ComprehensiveExportConfig.ExportProxy) -> String {
        if let u = ep.username, let p = ep.password {
            return "socks5://\(u):\(p)@\(ep.host):\(ep.port)"
        }
        return "socks5://\(ep.host):\(ep.port)"
    }
}

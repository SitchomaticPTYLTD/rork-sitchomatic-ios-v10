import Foundation
import Network
import Observation

nonisolated enum ConnectionMode: String, CaseIterable, Sendable {
    case dns = "DNS"
    case proxy = "Proxy"
    case openvpn = "OpenVPN"
    case wireguard = "WireGuard"

    var icon: String {
        switch self {
        case .dns: "lock.shield.fill"
        case .proxy: "network"
        case .openvpn: "shield.lefthalf.filled"
        case .wireguard: "lock.trianglebadge.exclamationmark.fill"
        }
    }

    var label: String {
        switch self {
        case .dns: "DNS-over-HTTPS"
        case .proxy: "SOCKS5 Proxy"
        case .openvpn: "OpenVPN"
        case .wireguard: "WireGuard"
        }
    }
}

nonisolated enum NetworkRegion: String, CaseIterable, Codable, Sendable {
    case usa = "USA"
    case au = "AU"

    var icon: String {
        switch self {
        case .usa: "flag.fill"
        case .au: "globe.asia.australia.fill"
        }
    }

    var label: String {
        switch self {
        case .usa: "United States"
        case .au: "Australia"
        }
    }
}

@Observable
@MainActor
class ProxyRotationService {
    static let shared = ProxyRotationService()

    var savedProxies: [ProxyConfig] = []
    var vpnConfigs: [OpenVPNConfig] = []
    var wgConfigs: [WireGuardConfig] = []

    var currentProxyIndex: Int = 0
    var currentWGIndex: Int = 0
    var currentOVPNIndex: Int = 0

    var rotateAfterDisabled: Bool = true
    var lastImportReport: ImportReport?

    var connectionMode: ConnectionMode = .dns {
        didSet { persistConnectionMode() }
    }

    var networkRegion: NetworkRegion = .usa {
        didSet { persistNetworkRegion() }
    }

    struct ImportReport {
        let added: Int
        let duplicates: Int
        let failed: [String]
        var total: Int { added + duplicates + failed.count }
    }

    private let proxyPersistKey = "saved_socks5_proxies_ppsr_v1"
    private let connectionModePersistKey = "connection_mode_ppsr_v1"
    private let networkRegionPersistKey = "network_region_v1"
    private let vpnPersistKey = "openvpn_configs_ppsr_v1"
    private let wgPersistKey = "wireguard_configs_ppsr_v1"

    private let logger = DebugLogger.shared

    init() {
        loadProxies()
        loadConnectionMode()
        loadVPNConfigs()
        loadWGConfigs()
        loadNetworkRegion()
        logger.log("ProxyRotation: init — proxies:\(savedProxies.count) vpn:\(vpnConfigs.count) wg:\(wgConfigs.count) region:\(networkRegion.rawValue)", category: .proxy, level: .info)
    }

    // MARK: - Convenience aliases for unified API callers

    var unifiedConnectionMode: ConnectionMode {
        get { connectionMode }
        set { connectionMode = newValue }
    }

    var unifiedProxies: [ProxyConfig] { savedProxies }
    var unifiedVPNConfigs: [OpenVPNConfig] { vpnConfigs }
    var unifiedWGConfigs: [WireGuardConfig] { wgConfigs }

    func setUnifiedConnectionMode(_ mode: ConnectionMode) {
        connectionMode = mode
        logger.log("ProxyRotation: connection mode set to \(mode.label)", category: .proxy, level: .success)
    }

    func importUnifiedProxy(_ text: String) -> ImportReport {
        bulkImportSOCKS5(text)
    }

    func importUnifiedVPNConfig(_ config: OpenVPNConfig) {
        importVPNConfig(config)
    }

    func importUnifiedWGConfigs(_ configs: [WireGuardConfig]) -> ImportReport {
        bulkImportWGConfigs(configs)
    }

    func clearAllUnifiedProxies() {
        removeAllProxies()
    }

    func clearAllUnifiedVPNConfigs() {
        clearAllVPNConfigs()
    }

    func clearAllUnifiedWGConfigs() {
        clearAllWGConfigs()
    }

    func testAllUnifiedProxies() async {
        await testAllProxies()
    }

    func testAllUnifiedVPNConfigs() async {
        await testAllVPNConfigs()
    }

    func testAllUnifiedWGConfigs() async {
        await testAllWGConfigs()
    }

    func syncAllNetworkConfigsAcrossTargets() {}

    // MARK: - Proxy Import

    func bulkImportSOCKS5(_ text: String) -> ImportReport {
        let expandedLines = expandProxyLines(text)

        var added = 0
        var duplicates = 0
        var failed: [String] = []

        for line in expandedLines {
            if let proxy = parseProxyLine(line) {
                let isDuplicate = savedProxies.contains { $0.host == proxy.host && $0.port == proxy.port && $0.username == proxy.username }
                if isDuplicate {
                    duplicates += 1
                } else {
                    savedProxies.append(proxy)
                    added += 1
                }
            } else {
                failed.append(line)
            }
        }

        if added > 0 { persistProxies() }
        let report = ImportReport(added: added, duplicates: duplicates, failed: failed)
        lastImportReport = report
        return report
    }

    private func expandProxyLines(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var expandedLines: [String] = []
        for line in rawLines {
            if line.contains("\t") {
                expandedLines.append(contentsOf: line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else if line.contains(" ") && !line.contains("://") {
                expandedLines.append(contentsOf: line.components(separatedBy: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else {
                expandedLines.append(line)
            }
        }
        return expandedLines
    }

    private func parseProxyLine(_ raw: String) -> ProxyConfig? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let schemePatterns = ["socks5h://", "socks5://", "socks4://", "socks://", "http://", "https://"]
        for scheme in schemePatterns {
            if line.lowercased().hasPrefix(scheme) {
                line = String(line.dropFirst(scheme.count))
                break
            }
        }

        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !line.isEmpty else { return nil }

        var username: String?
        var password: String?
        var hostPort: String

        if let atIndex = line.lastIndex(of: "@") {
            let authPart = String(line[line.startIndex..<atIndex])
            hostPort = String(line[line.index(after: atIndex)...])

            let authComponents = splitFirst(authPart, separator: ":")
            if let pw = authComponents.rest {
                username = authComponents.first
                password = pw
            } else {
                username = authPart
            }
        } else {
            let colonCount = line.filter({ $0 == ":" }).count
            if colonCount >= 3 {
                let parts = line.components(separatedBy: ":")
                if parts.count == 4, let _ = Int(parts[3]) {
                    username = parts[0]
                    password = parts[1]
                    hostPort = "\(parts[2]):\(parts[3])"
                } else if parts.count == 4, let _ = Int(parts[1]) {
                    hostPort = "\(parts[0]):\(parts[1])"
                    username = parts[2]
                    password = parts[3]
                } else {
                    hostPort = line
                }
            } else {
                hostPort = line
            }
        }

        hostPort = hostPort.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !hostPort.isEmpty else { return nil }

        let hpParts = hostPort.components(separatedBy: ":")
        guard hpParts.count >= 2 else { return nil }

        let portString = hpParts.last?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let port = Int(portString), port > 0, port <= 65535 else { return nil }

        let host = hpParts.dropLast().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }

        let validHostChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let hostChars = CharacterSet(charactersIn: host)
        guard validHostChars.isSuperset(of: hostChars) || isValidIPv4(host) else { return nil }

        if let u = username, u.isEmpty { username = nil }
        if let p = password, p.isEmpty { password = nil }

        return ProxyConfig(host: host, port: port, username: username, password: password)
    }

    private func splitFirst(_ s: String, separator: Character) -> (first: String, rest: String?) {
        if let idx = s.firstIndex(of: separator) {
            return (String(s[s.startIndex..<idx]), String(s[s.index(after: idx)...]))
        }
        return (s, nil)
    }

    private func isValidIPv4(_ host: String) -> Bool {
        let octets = host.components(separatedBy: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let num = Int(octet) else { return false }
            return num >= 0 && num <= 255
        }
    }

    // MARK: - Proxy Rotation

    func nextWorkingProxy() -> ProxyConfig? {
        let working = savedProxies.filter(\.isWorking)
        guard !working.isEmpty else {
            return savedProxies.isEmpty ? nil : savedProxies[currentProxyIndex % savedProxies.count]
        }
        currentProxyIndex = currentProxyIndex % working.count
        let proxy = working[currentProxyIndex]
        currentProxyIndex += 1
        return proxy
    }

    // MARK: - WireGuard Config Rotation

    func nextEnabledWGConfig() -> WireGuardConfig? {
        let configs = wgConfigs.filter { $0.isEnabled }
        guard !configs.isEmpty else { return nil }
        let idx = currentWGIndex % configs.count
        currentWGIndex = idx + 1
        return configs[idx]
    }

    func nextReachableWGConfig() -> WireGuardConfig? {
        let reachable = wgConfigs.filter { $0.isEnabled && $0.isReachable }
        if !reachable.isEmpty {
            let idx = currentWGIndex % reachable.count
            currentWGIndex = idx + 1
            return reachable[idx]
        }
        return nextEnabledWGConfig()
    }

    // MARK: - OpenVPN Config Rotation

    func nextEnabledOVPNConfig() -> OpenVPNConfig? {
        let configs = vpnConfigs.filter { $0.isEnabled }
        guard !configs.isEmpty else { return nil }
        let idx = currentOVPNIndex % configs.count
        currentOVPNIndex = idx + 1
        return configs[idx]
    }

    func nextReachableOVPNConfig() -> OpenVPNConfig? {
        let reachable = vpnConfigs.filter { $0.isEnabled && $0.isReachable }
        if !reachable.isEmpty {
            let idx = currentOVPNIndex % reachable.count
            currentOVPNIndex = idx + 1
            return reachable[idx]
        }
        return nextEnabledOVPNConfig()
    }

    func resetRotationIndexes() {
        currentProxyIndex = 0
        currentWGIndex = 0
        currentOVPNIndex = 0
    }

    func networkSummary() -> String {
        switch connectionMode {
        case .dns:
            return "Direct (DNS)"
        case .proxy:
            let count = savedProxies.filter(\.isWorking).count
            let total = savedProxies.count
            return "SOCKS5 (\(count)/\(total) working)"
        case .wireguard:
            let enabled = wgConfigs.filter { $0.isEnabled }.count
            let total = wgConfigs.count
            return "WireGuard (\(enabled)/\(total) enabled)"
        case .openvpn:
            let enabled = vpnConfigs.filter { $0.isEnabled }.count
            let total = vpnConfigs.count
            return "OpenVPN (\(enabled)/\(total) enabled)"
        }
    }

    // MARK: - Proxy Status

    func markProxyWorking(_ proxy: ProxyConfig) {
        if let idx = savedProxies.firstIndex(where: { $0.id == proxy.id }) {
            savedProxies[idx].isWorking = true
            savedProxies[idx].lastTested = Date()
            savedProxies[idx].failCount = 0
            persistProxies()
        }
    }

    func markProxyFailed(_ proxy: ProxyConfig) {
        if let idx = savedProxies.firstIndex(where: { $0.id == proxy.id }) {
            savedProxies[idx].failCount += 1
            savedProxies[idx].lastTested = Date()
            if savedProxies[idx].failCount >= 3 {
                savedProxies[idx].isWorking = false
            }
            persistProxies()
        }
    }

    func removeProxy(_ proxy: ProxyConfig) {
        savedProxies.removeAll { $0.id == proxy.id }
        persistProxies()
    }

    func removeAllProxies() {
        savedProxies.removeAll()
        currentProxyIndex = 0
        persistProxies()
    }

    func removeDead() {
        savedProxies.removeAll { !$0.isWorking && $0.lastTested != nil }
        persistProxies()
    }

    func resetAllStatus() {
        for i in savedProxies.indices {
            savedProxies[i].isWorking = false
            savedProxies[i].lastTested = nil
            savedProxies[i].failCount = 0
        }
        persistProxies()
    }

    // MARK: - Proxy Testing

    func testAllProxies() async {
        let maxConcurrent = 5
        let proxySnapshot = savedProxies
        await withTaskGroup(of: (UUID, Bool).self) { group in
            var launched = 0
            for proxy in proxySnapshot {
                if launched >= maxConcurrent {
                    if let result = await group.next() {
                        applyTestResult(result)
                    }
                }
                group.addTask {
                    let working = await self.testSingleProxy(proxy)
                    return (proxy.id, working)
                }
                launched += 1
            }
            for await result in group {
                applyTestResult(result)
            }
        }
        persistProxies()
    }

    private func applyTestResult(_ result: (UUID, Bool)) {
        let (proxyId, working) = result
        if let idx = savedProxies.firstIndex(where: { $0.id == proxyId }) {
            savedProxies[idx].isWorking = working
            savedProxies[idx].lastTested = Date()
            if working { savedProxies[idx].failCount = 0 }
            else { savedProxies[idx].failCount += 1 }
        }
    }

    private nonisolated func testSingleProxy(_ proxy: ProxyConfig) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15

        var proxyDict: [String: Any] = [
            "SOCKSEnable": 1,
            "SOCKSProxy": proxy.host,
            "SOCKSPort": proxy.port,
        ]
        if let u = proxy.username { proxyDict["SOCKSUser"] = u }
        if let p = proxy.password { proxyDict["SOCKSPassword"] = p }
        config.connectionProxyDictionary = proxyDict

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let testURLs = [
            "https://api.ipify.org?format=json",
            "https://httpbin.org/ip",
            "https://ifconfig.me/ip"
        ]

        var lastErrorDesc = ""
        for urlString in testURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    return true
                }
            } catch {
                lastErrorDesc = error.localizedDescription
                continue
            }
        }
        Task { @MainActor in
            self.logger.log("ProxyTest FAIL: \(proxy.displayString) — \(lastErrorDesc)", category: .proxy, level: .debug)
        }
        return false
    }

    func exportProxies() -> String {
        formatProxyList(savedProxies)
    }

    private func formatProxyList(_ list: [ProxyConfig]) -> String {
        list.map { proxy in
            if let u = proxy.username, let p = proxy.password {
                return "socks5://\(u):\(p)@\(proxy.host):\(proxy.port)"
            } else {
                return "socks5://\(proxy.host):\(proxy.port)"
            }
        }.joined(separator: "\n")
    }

    var activeProxies: [ProxyConfig] {
        savedProxies
    }

    // MARK: - VPN Configs

    func importVPNConfig(_ config: OpenVPNConfig) {
        guard !vpnConfigs.contains(where: { $0.remoteHost == config.remoteHost && $0.remotePort == config.remotePort }) else { return }
        vpnConfigs.append(config)
        persistVPNConfigs()
    }

    func removeVPNConfig(_ config: OpenVPNConfig) {
        vpnConfigs.removeAll { $0.id == config.id }
        persistVPNConfigs()
    }

    func toggleVPNConfig(_ config: OpenVPNConfig, enabled: Bool) {
        if let idx = vpnConfigs.firstIndex(where: { $0.id == config.id }) { vpnConfigs[idx].isEnabled = enabled }
        persistVPNConfigs()
    }

    func markVPNConfigReachable(_ config: OpenVPNConfig, reachable: Bool, latencyMs: Int? = nil) {
        if let idx = vpnConfigs.firstIndex(where: { $0.id == config.id || $0.uniqueKey == config.uniqueKey }) {
            vpnConfigs[idx].isReachable = reachable
            vpnConfigs[idx].lastTested = Date()
            vpnConfigs[idx].lastLatencyMs = latencyMs
            if reachable {
                vpnConfigs[idx].failCount = 0
                vpnConfigs[idx].isEnabled = true
            } else {
                vpnConfigs[idx].failCount += 1
                if vpnConfigs[idx].failCount >= 2 { vpnConfigs[idx].isEnabled = false }
            }
        }
        persistVPNConfigs()
    }

    func testAllVPNConfigs() async {
        guard !vpnConfigs.isEmpty else { return }
        let maxConcurrent = 8
        let snapshot = vpnConfigs
        await withTaskGroup(of: (String, Bool, Int).self) { group in
            var launched = 0
            for config in snapshot {
                if launched >= maxConcurrent {
                    if let result = await group.next() {
                        applyVPNTestResult(result)
                    }
                }
                group.addTask {
                    let (reachable, latency) = await self.testOpenVPNEndpointReachability(config)
                    return (config.uniqueKey, reachable, latency)
                }
                launched += 1
            }
            for await result in group {
                applyVPNTestResult(result)
            }
        }
        persistVPNConfigs()
    }

    private func applyVPNTestResult(_ result: (String, Bool, Int)) {
        let (uniqueKey, reachable, latency) = result
        if let idx = vpnConfigs.firstIndex(where: { $0.uniqueKey == uniqueKey }) {
            vpnConfigs[idx].isReachable = reachable
            vpnConfigs[idx].lastTested = Date()
            vpnConfigs[idx].lastLatencyMs = reachable ? latency : nil
            if reachable {
                vpnConfigs[idx].failCount = 0
                vpnConfigs[idx].isEnabled = true
            } else {
                vpnConfigs[idx].failCount += 1
                if vpnConfigs[idx].failCount >= 2 { vpnConfigs[idx].isEnabled = false }
            }
        }
    }

    nonisolated func testOpenVPNEndpointReachability(_ config: OpenVPNConfig) async -> (Bool, Int) {
        let host = config.remoteHost
        let port = config.remotePort
        let start = Date()

        let dnsOk = await resolveHost(host)
        if !dnsOk {
            let dohOk = await resolveHostViaDoH(host)
            if !dohOk {
                Task { @MainActor in
                    self.logger.log("VPN reachability: DNS failed for \(host) (system + DoH)", category: .vpn, level: .warning)
                    self.logger.logHealing(category: .vpn, originalError: "DNS resolution failed for \(host)", healingAction: "Tried DoH fallback — also failed", succeeded: false)
                }
                return (false, 0)
            }
            Task { @MainActor in
                self.logger.logHealing(category: .vpn, originalError: "System DNS failed for \(host)", healingAction: "DoH fallback succeeded", succeeded: true)
            }
        }

        if await testTCPConnection(host: host, port: port, timeoutSeconds: 8) {
            return (true, Int(Date().timeIntervalSince(start) * 1000))
        }

        Task { @MainActor in
            self.logger.log("VPN reachability: TCP failed for \(host):\(port)", category: .vpn, level: .error, metadata: [
                "host": host, "port": "\(port)", "elapsed": "\(Int(Date().timeIntervalSince(start) * 1000))ms"
            ])
        }
        return (false, 0)
    }

    func clearAllVPNConfigs() {
        vpnConfigs.removeAll()
        persistVPNConfigs()
    }

    func removeUnreachableVPNConfigs() {
        vpnConfigs.removeAll { !$0.isReachable && $0.lastTested != nil }
        persistVPNConfigs()
    }

    // MARK: - WireGuard Configs

    func importWGConfig(_ config: WireGuardConfig) {
        guard !wgConfigs.contains(where: { $0.uniqueKey == config.uniqueKey }) else { return }
        wgConfigs.append(config)
        persistWGConfigs()
    }

    func bulkImportWGConfigs(_ configs: [WireGuardConfig]) -> ImportReport {
        var added = 0
        var duplicates = 0
        let failed: [String] = []
        var seenKeys = Set(wgConfigs.map(\.uniqueKey))
        for config in configs {
            if seenKeys.contains(config.uniqueKey) {
                duplicates += 1
            } else {
                seenKeys.insert(config.uniqueKey)
                wgConfigs.append(config)
                added += 1
            }
        }
        if added > 0 { persistWGConfigs() }
        let report = ImportReport(added: added, duplicates: duplicates, failed: failed)
        lastImportReport = report
        return report
    }

    func removeWGConfig(_ config: WireGuardConfig) {
        wgConfigs.removeAll { $0.id == config.id || $0.uniqueKey == config.uniqueKey }
        persistWGConfigs()
    }

    func toggleWGConfig(_ config: WireGuardConfig, enabled: Bool) {
        if let idx = wgConfigs.firstIndex(where: { $0.id == config.id || $0.uniqueKey == config.uniqueKey }) { wgConfigs[idx].isEnabled = enabled }
        persistWGConfigs()
    }

    func clearAllWGConfigs() {
        wgConfigs.removeAll()
        persistWGConfigs()
    }

    func markWGConfigReachable(_ config: WireGuardConfig, reachable: Bool) {
        if let idx = wgConfigs.firstIndex(where: { $0.id == config.id || $0.uniqueKey == config.uniqueKey }) {
            wgConfigs[idx].isReachable = reachable
            wgConfigs[idx].lastTested = Date()
            if !reachable { wgConfigs[idx].isEnabled = false }
        }
        persistWGConfigs()
    }

    func removeUnreachableWGConfigs() {
        wgConfigs.removeAll { !$0.isReachable && $0.lastTested != nil }
        persistWGConfigs()
    }

    func testAllWGConfigs() async {
        guard !wgConfigs.isEmpty else { return }
        let maxConcurrent = 8
        let snapshot = wgConfigs
        await withTaskGroup(of: (String, Bool).self) { group in
            var launched = 0
            for config in snapshot {
                if launched >= maxConcurrent {
                    if let result = await group.next() {
                        applyWGTestResult(result)
                    }
                }
                group.addTask {
                    let reachable = await self.testWGEndpointReachability(config)
                    return (config.uniqueKey, reachable)
                }
                launched += 1
            }
            for await result in group {
                applyWGTestResult(result)
            }
        }
        persistWGConfigs()
    }

    private func applyWGTestResult(_ result: (String, Bool)) {
        let (uniqueKey, reachable) = result
        if let idx = wgConfigs.firstIndex(where: { $0.uniqueKey == uniqueKey }) {
            wgConfigs[idx].isReachable = reachable
            wgConfigs[idx].lastTested = Date()
            if !reachable { wgConfigs[idx].isEnabled = false }
        }
    }

    nonisolated func testWGEndpointReachability(_ config: WireGuardConfig) async -> Bool {
        let host = config.endpointHost

        var dnsReachable = await resolveHost(host)
        if !dnsReachable {
            dnsReachable = await resolveHostViaDoH(host)
            if !dnsReachable {
                Task { @MainActor in
                    self.logger.log("WG reachability: DNS failed for \(host) (system + DoH)", category: .vpn, level: .warning)
                }
                return false
            }
            Task { @MainActor in
                self.logger.logHealing(category: .vpn, originalError: "System DNS failed for \(host)", healingAction: "DoH fallback succeeded", succeeded: true)
            }
        }

        return true
    }

    nonisolated func testWGEndpointWithLatency(_ config: WireGuardConfig) async -> (Bool, Int) {
        let start = Date()
        let reachable = await testWGEndpointReachability(config)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return (reachable, latency)
    }

    // MARK: - Persistence

    private func persistProxies() {
        persistProxyList(savedProxies, key: proxyPersistKey)
    }

    private func loadProxies() {
        let loaded = loadProxyList(key: proxyPersistKey)
        if !loaded.isEmpty {
            savedProxies = loaded
        }
    }

    private func persistProxyList(_ list: [ProxyConfig], key: String) {
        let encoded = list.map { p -> [String: Any] in
            var dict: [String: Any] = [
                "id": p.id.uuidString,
                "host": p.host,
                "port": p.port,
                "isWorking": p.isWorking,
                "failCount": p.failCount,
            ]
            if let u = p.username { dict["username"] = u }
            if let pw = p.password { dict["password"] = pw }
            if let d = p.lastTested { dict["lastTested"] = d.timeIntervalSince1970 }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: encoded) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadProxyList(key: String) -> [ProxyConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { dict -> ProxyConfig? in
            guard let host = dict["host"] as? String,
                  let port = dict["port"] as? Int else { return nil }
            let restoredID: UUID
            if let idString = dict["id"] as? String, let parsed = UUID(uuidString: idString) {
                restoredID = parsed
            } else {
                restoredID = UUID()
            }
            var proxy = ProxyConfig(
                id: restoredID,
                host: host,
                port: port,
                username: dict["username"] as? String,
                password: dict["password"] as? String
            )
            proxy.isWorking = dict["isWorking"] as? Bool ?? false
            proxy.failCount = dict["failCount"] as? Int ?? 0
            if let ts = dict["lastTested"] as? TimeInterval {
                proxy.lastTested = Date(timeIntervalSince1970: ts)
            }
            return proxy
        }
    }

    private func persistConnectionMode() {
        UserDefaults.standard.set(connectionMode.rawValue, forKey: connectionModePersistKey)
    }

    private func loadConnectionMode() {
        if let raw = UserDefaults.standard.string(forKey: connectionModePersistKey),
           let mode = ConnectionMode(rawValue: raw) {
            connectionMode = mode
        }
    }

    private func persistNetworkRegion() {
        UserDefaults.standard.set(networkRegion.rawValue, forKey: networkRegionPersistKey)
    }

    private func loadNetworkRegion() {
        if let raw = UserDefaults.standard.string(forKey: networkRegionPersistKey),
           let region = NetworkRegion(rawValue: raw) {
            networkRegion = region
        }
    }

    private func persistVPNConfigs() {
        do {
            let data = try JSONEncoder().encode(vpnConfigs)
            UserDefaults.standard.set(data, forKey: vpnPersistKey)
            logger.log("ProxyRotation: persisted \(vpnConfigs.count) VPN configs", category: .persistence, level: .debug)
        } catch {
            logger.logError("ProxyRotation: failed to persist VPN configs", error: error, category: .persistence)
        }
    }

    private func loadVPNConfigs() {
        if let data = UserDefaults.standard.data(forKey: vpnPersistKey),
           let configs = try? JSONDecoder().decode([OpenVPNConfig].self, from: data) {
            vpnConfigs = configs
        }
    }

    private func persistWGConfigs() {
        do {
            let data = try JSONEncoder().encode(wgConfigs)
            UserDefaults.standard.set(data, forKey: wgPersistKey)
            logger.log("ProxyRotation: persisted \(wgConfigs.count) WG configs", category: .persistence, level: .debug)
        } catch {
            logger.logError("ProxyRotation: failed to persist WG configs", error: error, category: .persistence)
        }
    }

    private func loadWGConfigs() {
        if let data = UserDefaults.standard.data(forKey: wgPersistKey),
           let configs = try? JSONDecoder().decode([WireGuardConfig].self, from: data) {
            wgConfigs = configs
        }
    }

    // MARK: - Network Utilities

    private nonisolated func resolveHost(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            var resolved = DarwinBoolean(false)
            CFHostStartInfoResolution(hostRef, .addresses, nil)
            let addresses = CFHostGetAddressing(hostRef, &resolved)
            if resolved.boolValue, let addrs = addresses?.takeUnretainedValue() as? [Data], !addrs.isEmpty {
                continuation.resume(returning: true)
            } else {
                continuation.resume(returning: false)
            }
        }
    }

    private nonisolated func resolveHostViaDoH(_ host: String) async -> Bool {
        let dohEndpoints = [
            "https://cloudflare-dns.com/dns-query?name=\(host)&type=A",
            "https://dns.google/dns-query?name=\(host)&type=A",
            "https://dns.quad9.net:5053/dns-query?name=\(host)&type=A"
        ]

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        for urlString in dohEndpoints {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 6
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answers = json["Answer"] as? [[String: Any]], !answers.isEmpty {
                        return true
                    }
                }
            } catch {
                continue
            }
        }
        return false
    }

    private nonisolated func testHTTPSHandshake(host: String) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        guard let url = URL(string: "https://\(host)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode < 500
            }
            return true
        } catch let error as NSError {
            if error.domain == NSURLErrorDomain {
                if error.code == NSURLErrorSecureConnectionFailed { return true }
                if error.code == NSURLErrorServerCertificateUntrusted { return true }
                if error.code == NSURLErrorServerCertificateHasBadDate { return true }
                if error.code == NSURLErrorServerCertificateHasUnknownRoot { return true }
            }
            return false
        }
    }

    private nonisolated func testTCPConnection(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let guard_ = ContinuationGuard()
            let queue = DispatchQueue(label: "tcp.test.\(host).\(port)")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guard_.tryConsume() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if guard_.tryConsume() {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                if guard_.tryConsume() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

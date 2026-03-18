import Foundation
import WebKit

nonisolated enum ActiveNetworkConfig: Sendable {
    case direct
    case socks5(ProxyConfig)
    case wireGuardDNS(WireGuardConfig)
    case openVPNProxy(OpenVPNConfig)

    var label: String {
        switch self {
        case .direct: "Direct"
        case .socks5(let p): "SOCKS5 \(p.displayString)"
        case .wireGuardDNS(let wg): "WG \(wg.displayString)"
        case .openVPNProxy(let ovpn): "OVPN \(ovpn.displayString)"
        }
    }

    var dnsServers: [String]? {
        switch self {
        case .wireGuardDNS(let wg):
            let raw = wg.interfaceDNS
            guard !raw.isEmpty else { return nil }
            return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default:
            return nil
        }
    }
}

@MainActor
class NetworkSessionFactory {
    static let shared = NetworkSessionFactory()

    private let proxyService = ProxyRotationService.shared
    private let logger = DebugLogger.shared

    private var wgIndex: Int = 0
    private var ovpnIndex: Int = 0

    func nextConfig() -> ActiveNetworkConfig {
        let mode = proxyService.connectionMode

        switch mode {
        case .dns:
            return .direct

        case .proxy:
            if let proxy = proxyService.nextWorkingProxy() {
                logger.log("NetworkFactory: assigned SOCKS5 \(proxy.displayString)", category: .proxy, level: .debug)
                return .socks5(proxy)
            }
            logger.log("NetworkFactory: no working SOCKS5 proxy — falling back to direct", category: .proxy, level: .warning)
            return .direct

        case .wireguard:
            if let wg = nextWGConfig() {
                logger.log("NetworkFactory: assigned WG \(wg.displayString)", category: .vpn, level: .debug)
                return .wireGuardDNS(wg)
            }
            logger.log("NetworkFactory: no enabled WG config — falling back to direct", category: .vpn, level: .warning)
            return .direct

        case .openvpn:
            if let ovpn = nextOVPNConfig() {
                logger.log("NetworkFactory: assigned OVPN \(ovpn.displayString)", category: .vpn, level: .debug)
                return .openVPNProxy(ovpn)
            }
            logger.log("NetworkFactory: no enabled OVPN config — falling back to direct", category: .vpn, level: .warning)
            return .direct
        }
    }

    func buildURLSessionConfiguration(for config: ActiveNetworkConfig) -> URLSessionConfiguration {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfig.httpShouldSetCookies = false
        sessionConfig.httpCookieAcceptPolicy = .never

        switch config {
        case .direct:
            break

        case .socks5(let proxy):
            var proxyDict: [String: Any] = [
                "SOCKSEnable": 1,
                "SOCKSProxy": proxy.host,
                "SOCKSPort": proxy.port,
            ]
            if let u = proxy.username { proxyDict["SOCKSUser"] = u }
            if let p = proxy.password { proxyDict["SOCKSPassword"] = p }
            sessionConfig.connectionProxyDictionary = proxyDict
            logger.log("URLSession configured with SOCKS5: \(proxy.displayString)", category: .proxy, level: .trace)

        case .wireGuardDNS(let wg):
            let endpoint = wg.endpointHost
            let port = wg.endpointPort
            sessionConfig.connectionProxyDictionary = [
                "SOCKSEnable": 0,
            ]
            if let dnsServers = config.dnsServers, !dnsServers.isEmpty {
                logger.log("URLSession WG DNS: \(dnsServers.joined(separator: ", ")) via \(endpoint):\(port)", category: .vpn, level: .trace)
            }

        case .openVPNProxy(let ovpn):
            let host = ovpn.remoteHost
            let port = ovpn.remotePort
            if ovpn.proto == "tcp" {
                sessionConfig.connectionProxyDictionary = [
                    "HTTPEnable": 1,
                    "HTTPProxy": host,
                    "HTTPPort": port,
                    "HTTPSEnable": 1,
                    "HTTPSProxy": host,
                    "HTTPSPort": port,
                ]
                logger.log("URLSession configured with OVPN TCP proxy: \(host):\(port)", category: .vpn, level: .trace)
            }
        }

        return sessionConfig
    }

    func configureWKWebView(config wkConfig: WKWebViewConfiguration, networkConfig: ActiveNetworkConfig) {
        switch networkConfig {
        case .socks5(let proxy):
            let pacScript = generatePACScript(proxyHost: proxy.host, proxyPort: proxy.port, type: "SOCKS5")
            injectPACProxy(into: wkConfig, pacScript: pacScript)
            logger.log("WKWebView configured with SOCKS5 PAC: \(proxy.displayString)", category: .proxy, level: .debug)

        case .wireGuardDNS(let wg):
            if let dnsServers = networkConfig.dnsServers, !dnsServers.isEmpty {
                let dnsJS = buildDNSRoutingScript(servers: dnsServers, endpoint: wg.endpointHost)
                let userScript = WKUserScript(source: dnsJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                wkConfig.userContentController.addUserScript(userScript)
                logger.log("WKWebView WG DNS routing injected: \(dnsServers.joined(separator: ", "))", category: .vpn, level: .debug)
            }

        case .openVPNProxy(let ovpn):
            if ovpn.proto == "tcp" {
                let pacScript = generatePACScript(proxyHost: ovpn.remoteHost, proxyPort: ovpn.remotePort, type: "PROXY")
                injectPACProxy(into: wkConfig, pacScript: pacScript)
                logger.log("WKWebView configured with OVPN proxy: \(ovpn.displayString)", category: .vpn, level: .debug)
            }

        case .direct:
            break
        }
    }

    func resetRotationIndexes() {
        wgIndex = 0
        ovpnIndex = 0
    }

    private func nextWGConfig() -> WireGuardConfig? {
        let configs = proxyService.wgConfigs.filter { $0.isEnabled }
        guard !configs.isEmpty else { return nil }
        let index = wgIndex % configs.count
        wgIndex = index + 1
        return configs[index]
    }

    private func nextOVPNConfig() -> OpenVPNConfig? {
        let configs = proxyService.vpnConfigs.filter { $0.isEnabled }
        guard !configs.isEmpty else { return nil }
        let index = ovpnIndex % configs.count
        ovpnIndex = index + 1
        return configs[index]
    }

    private func generatePACScript(proxyHost: String, proxyPort: Int, type: String) -> String {
        """
        function FindProxyForURL(url, host) {
            if (isPlainHostName(host) || host === "localhost" || host === "127.0.0.1") {
                return "DIRECT";
            }
            return "\(type) \(proxyHost):\(proxyPort); DIRECT";
        }
        """
    }

    private func injectPACProxy(into config: WKWebViewConfiguration, pacScript: String) {
        let js = """
        (function() {
            window.__networkProxy = true;
            window.__proxyPAC = `\(pacScript.replacingOccurrences(of: "`", with: "\\`"))`;
        })();
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
    }

    private func buildDNSRoutingScript(servers: [String], endpoint: String) -> String {
        """
        (function() {
            window.__wgDNS = [\(servers.map { "'\($0)'" }.joined(separator: ","))];
            window.__wgEndpoint = '\(endpoint)';
            window.__networkRouted = true;
        })();
        """
    }
}

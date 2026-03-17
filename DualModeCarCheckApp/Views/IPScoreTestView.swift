import SwiftUI
import WebKit

@Observable
class IPScoreSession: Identifiable {
    let id: UUID = UUID()
    let index: Int
    var url: URL = URL(string: "https://ipscore.io")!
    var isLoading: Bool = true
    var currentURL: String = ""
    var pageTitle: String = ""
    var assignedVPNServer: String?
    var assignedVPNIP: String?
    var assignedVPNCountry: String?
    var assignedProxy: String?
    var networkLabel: String = "Direct"
    var startedAt: Date = Date()
    var detectedIP: String?
    var status: SessionStatus = .loading

    nonisolated enum SessionStatus: String, Sendable {
        case loading = "Loading"
        case loaded = "Loaded"
        case failed = "Failed"
    }

    var elapsedSeconds: Int {
        Int(Date().timeIntervalSince(startedAt))
    }

    init(index: Int) {
        self.index = index
    }
}

struct IPScoreTestView: View {
    @State private var sessions: [IPScoreSession] = []
    @State private var isRunning: Bool = false
    @State private var viewMode: ViewMode = .list
    @State private var showNetworkSheet: Bool = false
    @State private var elapsedTimer: Timer?
    @State private var timerTick: Int = 0

    private let proxyService = ProxyRotationService.shared
    private let nordService = NordVPNService.shared
    private let logger = DebugLogger.shared
    private let sessionCount = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if sessions.isEmpty {
                    emptyState
                } else if viewMode == .list {
                    sessionListView
                } else {
                    sessionTileView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("IP Score Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MainMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !sessions.isEmpty {
                            ViewModeToggle(mode: $viewMode, accentColor: .indigo)
                        }
                        Button {
                            showNetworkSheet = true
                        } label: {
                            Image(systemName: "network")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                }
            }
            .sheet(isPresented: $showNetworkSheet) {
                networkInfoSheet
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            elapsedTimer?.invalidate()
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                let loadedCount = sessions.filter({ $0.status == .loaded }).count
                let failedCount = sessions.filter({ $0.status == .failed }).count
                let loadingCount = sessions.filter({ $0.status == .loading }).count

                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("\(loadedCount)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("OK")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                }

                HStack(spacing: 6) {
                    Circle().fill(.yellow).frame(width: 7, height: 7)
                    Text("\(loadingCount)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                    Text("LOAD")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.yellow.opacity(0.6))
                }

                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("\(failedCount)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                    Text("FAIL")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.6))
                }

                Spacer()

                let mode = proxyService.connectionMode(for: .ppsr)
                HStack(spacing: 4) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(mode.label)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.indigo.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.indigo.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentTransition(.numericText())
            .animation(.snappy, value: timerTick)

            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)

            HStack(spacing: 10) {
                if isRunning {
                    Button {
                        stopSessions()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("STOP")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.red.opacity(0.12))
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        launchSessions()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("LAUNCH 8 SESSIONS")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [.indigo, .cyan], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                    }
                    .sensoryFeedback(.impact(weight: .heavy), trigger: isRunning)
                }

                Spacer()

                if !sessions.isEmpty {
                    Button {
                        sessions.removeAll()
                        isRunning = false
                        elapsedTimer?.invalidate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .bold))
                            Text("CLEAR")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            Text("IP Score Test")
                .font(.title2.bold())

            Text("Launch 8 concurrent sessions to ipscore.io\nto verify each uses a different proxy or VPN address.\nNo automation — pure network isolation test.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                networkInfoRow(icon: proxyService.connectionMode(for: .ppsr).icon, label: "Mode", value: proxyService.connectionMode(for: .ppsr).label)
                networkInfoRow(icon: "server.rack", label: "Nord Servers", value: "\(nordService.recommendedServers.count) loaded")
                networkInfoRow(icon: "network", label: "Proxies", value: "\(proxyService.savedProxies.count) configured")
                networkInfoRow(icon: "lock.shield.fill", label: "WireGuard", value: "\(proxyService.ppsrWGConfigs.count) configs")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func networkInfoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var sessionListView: some View {
        List {
            ForEach(sessions) { session in
                IPScoreSessionRow(session: session, timerTick: timerTick)
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
    }

    private var sessionTileView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(sessions) { session in
                    IPScoreSessionTile(session: session, timerTick: timerTick)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private var networkInfoSheet: some View {
        NavigationStack {
            List {
                Section("Connection Mode") {
                    LabeledContent("PPSR") { Text(proxyService.networkSummary(for: .ppsr)) }
                    
                }

                Section("NordVPN") {
                    LabeledContent("Profile") { Text(nordService.activeKeyProfile.rawValue) }
                    LabeledContent("Servers Loaded") { Text("\(nordService.recommendedServers.count)") }
                    LabeledContent("Has Private Key") { Text(nordService.hasPrivateKey ? "Yes" : "No").foregroundStyle(nordService.hasPrivateKey ? .green : .red) }
                }

                Section("Proxies") {
                    LabeledContent("SOCKS5") { Text("\(proxyService.savedProxies.count)") }
                    LabeledContent("Working") { Text("\(proxyService.savedProxies.filter(\.isWorking).count)") }
                }

                Section("VPN Configs") {
                    LabeledContent("OpenVPN") { Text("\(proxyService.ppsrVPNConfigs.count)") }
                    LabeledContent("WireGuard") { Text("\(proxyService.ppsrWGConfigs.count)") }
                }

                if !sessions.isEmpty {
                    Section("Session Network Assignments") {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("S\(session.index)")
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.indigo.opacity(0.15))
                                        .clipShape(.rect(cornerRadius: 4))
                                    Text(session.networkLabel)
                                        .font(.system(.caption, design: .monospaced))
                                }
                                if let server = session.assignedVPNServer {
                                    Text(server)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                if let ip = session.assignedVPNIP {
                                    Text(ip)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Network Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showNetworkSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func launchSessions() {
        sessions.removeAll()
        isRunning = true
        timerTick = 0

        let connectionMode = proxyService.connectionMode(for: .ppsr)

        for i in 0..<sessionCount {
            let session = IPScoreSession(index: i + 1)
            assignNetworkToSession(session, index: i, mode: connectionMode)
            sessions.append(session)
        }

        logger.log("IPScoreTest: launched \(sessionCount) concurrent sessions — mode: \(connectionMode.label)", category: .automation, level: .info)

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                timerTick += 1
                let allDone = sessions.allSatisfy { $0.status != .loading }
                if allDone {
                    elapsedTimer?.invalidate()
                    isRunning = false
                    let loaded = sessions.filter { $0.status == .loaded }.count
                    let failed = sessions.filter { $0.status == .failed }.count
                    logger.log("IPScoreTest: all sessions complete — \(loaded) loaded, \(failed) failed", category: .automation, level: loaded == sessionCount ? .success : .warning)
                }
            }
        }
    }

    private func assignNetworkToSession(_ session: IPScoreSession, index: Int, mode: ConnectionMode) {
        switch mode {
        case .proxy:
            if let proxy = proxyService.nextWorkingProxy(for: .ppsr) {
                session.assignedProxy = proxy.displayString
                session.networkLabel = "SOCKS5 \(proxy.host):\(proxy.port)"
            } else if !proxyService.savedProxies.isEmpty {
                let proxy = proxyService.savedProxies[index % proxyService.savedProxies.count]
                session.assignedProxy = proxy.displayString
                session.networkLabel = "SOCKS5 \(proxy.host):\(proxy.port)"
            } else {
                session.networkLabel = "Direct (no proxies)"
            }

        case .wireguard:
            if let wg = proxyService.nextEnabledWGConfig(for: .ppsr) {
                session.assignedVPNServer = wg.fileName
                session.assignedVPNIP = wg.peerEndpoint
                session.networkLabel = "WG \(wg.fileName)"
                if let server = nordService.recommendedServers.first(where: { $0.hostname == wg.fileName }) {
                    session.assignedVPNCountry = server.country
                }
            } else {
                session.networkLabel = "WG (none available)"
            }

        case .openvpn:
            if let ovpn = proxyService.nextEnabledOVPNConfig(for: .ppsr) {
                session.assignedVPNServer = ovpn.fileName
                session.assignedVPNIP = ovpn.remoteHost
                session.networkLabel = "OVPN \(ovpn.fileName)"
                if let server = nordService.recommendedServers.first(where: { $0.hostname == ovpn.remoteHost || $0.hostname == ovpn.fileName }) {
                    session.assignedVPNCountry = server.country
                }
            } else {
                session.networkLabel = "OVPN (none available)"
            }

        case .dns:
            if !nordService.recommendedServers.isEmpty {
                let server = nordService.recommendedServers[index % nordService.recommendedServers.count]
                session.assignedVPNServer = server.hostname
                session.assignedVPNIP = server.station
                session.assignedVPNCountry = server.country
                session.networkLabel = "Nord \(server.hostname.prefix(20))"
            } else {
                session.networkLabel = "Direct"
            }
        }
    }

    private func stopSessions() {
        isRunning = false
        elapsedTimer?.invalidate()
        for session in sessions where session.status == .loading {
            session.status = .failed
        }
        logger.log("IPScoreTest: sessions stopped by user", category: .automation, level: .warning)
    }
}

struct IPScoreSessionRow: View {
    let session: IPScoreSession
    let timerTick: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Text("S\(session.index)")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("ipscore.io")
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        Text(session.status.rawValue)
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(statusColor)
                    }

                    Text(session.networkLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let server = session.assignedVPNServer {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.indigo)
                            Text("Nord: \(server)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.indigo.opacity(0.8))
                            if let country = session.assignedVPNCountry {
                                Text("(\(country))")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.indigo.opacity(0.5))
                            }
                        }
                        .lineLimit(1)
                    }

                    if let ip = session.assignedVPNIP {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.cyan.opacity(0.7))
                            Text(ip)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                    }

                    if let proxy = session.assignedProxy {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange.opacity(0.7))
                            Text(proxy)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.orange.opacity(0.7))
                        }
                        .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if session.status == .loading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.indigo)
                    } else {
                        Image(systemName: session.status == .loaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    Text("\(session.elapsedSeconds)s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            if session.status == .loading {
                ProgressView(value: min(Double(session.elapsedSeconds) / 15.0, 0.95))
                    .tint(.indigo)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.status {
        case .loading: .indigo
        case .loaded: .green
        case .failed: .red
        }
    }
}

struct IPScoreSessionTile: View {
    let session: IPScoreSession
    let timerTick: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("S\(session.index)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 4))

                Spacer()

                if session.status == .loading {
                    ProgressView().controlSize(.mini).tint(.indigo)
                } else {
                    Image(systemName: session.status == .loaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(statusColor)
                        .font(.system(size: 14))
                }
            }

            Text(session.networkLabel)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let server = session.assignedVPNServer {
                HStack(spacing: 3) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 8, weight: .bold))
                    Text(server.prefix(18))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.indigo.opacity(0.8))
                .lineLimit(1)
            }

            if let ip = session.assignedVPNIP {
                Text(ip)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text("\(session.elapsedSeconds)s")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(12)
        .frame(minHeight: 120)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch session.status {
        case .loading: .indigo
        case .loaded: .green
        case .failed: .red
        }
    }
}

import SwiftUI

struct DeviceNetworkSettingsView: View {
    private let proxyService = ProxyRotationService.shared
    private let dnsService = PPSRDoHService.shared
    @State private var proxyImportText: String = ""
    @State private var showProxyImport: Bool = false
    @State private var showVPNFilePicker: Bool = false
    @State private var showWGFilePicker: Bool = false
    @State private var dnsImportText: String = ""
    @State private var showDNSImport: Bool = false
    @State private var dnsTestComplete: Bool = false

    var body: some View {
        List {
            connectionModeSection
            dnsSection
            proxySection
            vpnSection
            wireguardSection
            regionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Network Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProxyImport) { proxyImportSheet }
        .sheet(isPresented: $showDNSImport) { dnsImportSheet }
    }

    private var connectionModeSection: some View {
        Section {
            Picker("Connection Mode", selection: Binding(
                get: { proxyService.unifiedConnectionMode },
                set: { proxyService.setUnifiedConnectionMode($0) }
            )) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Active Mode")
        } footer: {
            Text("Select how network requests are routed during PPSR checks.")
        }
    }

    private var regionSection: some View {
        Section {
            Picker("Region", selection: Binding(
                get: { proxyService.networkRegion },
                set: { proxyService.networkRegion = $0 }
            )) {
                ForEach(NetworkRegion.allCases, id: \.self) { region in
                    Label(region.label, systemImage: region.icon).tag(region)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Network Region")
        }
    }

    private var dnsSection: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    Task {
                        dnsTestComplete = false
                        _ = await dnsService.testAllProviders()
                        dnsTestComplete = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if dnsService.isTestingAll {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(dnsService.isTestingAll ? "Testing..." : "Test All DNS")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(dnsService.isTestingAll)

                if dnsTestComplete || dnsService.managedProviders.contains(where: { $0.autoDisabledBySystem }) {
                    Button {
                        dnsService.enableAll()
                        dnsTestComplete = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Re-enable")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            ForEach(dnsService.managedProviders) { provider in
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(providerIconColor(provider))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.name).font(.subheadline.bold())
                            if provider.autoDisabledBySystem {
                                Text("AUTO-OFF")
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(.rect(cornerRadius: 4))
                            }
                        }
                        Text(provider.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    dnsStatusBadge(provider)
                }
                .swipeActions(edge: .trailing) {
                    if !provider.isDefault {
                        Button(role: .destructive) {
                            dnsService.deleteProvider(id: provider.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    Button {
                        dnsService.toggleProvider(id: provider.id, enabled: !provider.isEnabled)
                    } label: {
                        Label(provider.isEnabled ? "Disable" : "Enable", systemImage: provider.isEnabled ? "xmark.circle" : "checkmark.circle")
                    }
                    .tint(provider.isEnabled ? .orange : .green)
                }
            }
            Button { showDNSImport = true } label: {
                Label("Add DNS Provider", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            HStack {
                Text("DNS-over-HTTPS (\(dnsService.managedProviders.filter(\.isEnabled).count) active)")
                Spacer()
                if dnsService.healthyProviderCount < dnsService.managedProviders.count && dnsService.healthyProviderCount > 0 {
                    Text("\(dnsService.healthyProviderCount) healthy")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func dnsStatusBadge(_ provider: ManagedDoHProvider) -> some View {
        switch provider.lastTestStatus {
        case .untested:
            if provider.isEnabled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
        case .testing:
            ProgressView().controlSize(.mini)
        case .passed(let latencyMs):
            Text("\(latencyMs)ms")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(.rect(cornerRadius: 4))
        case .failed:
            Text("FAIL")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .clipShape(.rect(cornerRadius: 4))
        case .autoDisabled:
            Text("DISABLED")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(.rect(cornerRadius: 4))
        }
    }

    private func providerIconColor(_ provider: ManagedDoHProvider) -> Color {
        if provider.autoDisabledBySystem { return .orange }
        if !provider.isEnabled { return .secondary }
        switch provider.lastTestStatus {
        case .failed, .autoDisabled: return .red
        case .passed: return .green
        default: return provider.isEnabled ? .green : .secondary
        }
    }

    private var proxySection: some View {
        Section {
            if proxyService.savedProxies.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    Text("No proxies configured").foregroundStyle(.secondary)
                }
            } else {
                ForEach(proxyService.savedProxies) { proxy in
                    HStack(spacing: 10) {
                        Image(systemName: "network").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(proxy.host):\(proxy.port)").font(.system(.subheadline, design: .monospaced))
                            if proxy.username != nil {
                                Text("Authenticated").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { proxyService.removeProxy(proxy) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            Button { showProxyImport = true } label: {
                Label("Import SOCKS5 Proxies", systemImage: "plus.circle").foregroundStyle(.blue)
            }
        } header: {
            Text("SOCKS5 Proxies (\(proxyService.savedProxies.count))")
        }
    }

    private var vpnSection: some View {
        Section {
            if proxyService.vpnConfigs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.secondary)
                    Text("No OpenVPN configs").foregroundStyle(.secondary)
                }
            } else {
                ForEach(proxyService.vpnConfigs) { vpn in
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(vpn.isEnabled ? .indigo : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vpn.fileName).font(.subheadline.bold())
                            Text("\(vpn.remoteHost):\(vpn.remotePort) · \(vpn.proto)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if vpn.isEnabled {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { proxyService.removeVPNConfig(vpn) } label: { Label("Delete", systemImage: "trash") }
                        Button { proxyService.toggleVPNConfig(vpn, enabled: !vpn.isEnabled) } label: {
                            Label(vpn.isEnabled ? "Disable" : "Enable", systemImage: vpn.isEnabled ? "xmark.circle" : "checkmark.circle")
                        }
                        .tint(vpn.isEnabled ? .orange : .green)
                    }
                }
            }
        } header: {
            Text("OpenVPN (\(proxyService.vpnConfigs.filter(\.isEnabled).count) active)")
        }
    }

    private var wireguardSection: some View {
        Section {
            if proxyService.wgConfigs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill").foregroundStyle(.secondary)
                    Text("No WireGuard configs").foregroundStyle(.secondary)
                }
            } else {
                ForEach(proxyService.wgConfigs) { wg in
                    HStack(spacing: 10) {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(wg.isEnabled ? .cyan : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wg.fileName).font(.subheadline.bold())
                        }
                        Spacer()
                        if wg.isEnabled {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { proxyService.removeWGConfig(wg) } label: { Label("Delete", systemImage: "trash") }
                        Button { proxyService.toggleWGConfig(wg, enabled: !wg.isEnabled) } label: {
                            Label(wg.isEnabled ? "Disable" : "Enable", systemImage: wg.isEnabled ? "xmark.circle" : "checkmark.circle")
                        }
                        .tint(wg.isEnabled ? .orange : .green)
                    }
                }
            }
        } header: {
            Text("WireGuard (\(proxyService.wgConfigs.filter(\.isEnabled).count) active)")
        }
    }

    private var proxyImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import SOCKS5 Proxies").font(.headline)
                    Text("Paste SOCKS5 proxy URLs, one per line.\nFormat: socks5://user:pass@host:port").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $proxyImportText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Color(.tertiarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 10))
                    .frame(minHeight: 180)
                Spacer()
            }
            .padding()
            .navigationTitle("Import Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showProxyImport = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        _ = proxyService.bulkImportSOCKS5(proxyImportText)
                        proxyImportText = ""
                        showProxyImport = false
                    }
                    .disabled(proxyImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var dnsImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add DNS Provider").font(.headline)
                    Text("Paste DoH URLs, one per line.\nFormat: https://dns.example.com/dns-query").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $dnsImportText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Color(.tertiarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 10))
                    .frame(minHeight: 180)
                Spacer()
            }
            .padding()
            .navigationTitle("Add DNS").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDNSImport = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        _ = dnsService.bulkImportProviders(dnsImportText)
                        dnsImportText = ""
                        showDNSImport = false
                    }
                    .disabled(dnsImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}

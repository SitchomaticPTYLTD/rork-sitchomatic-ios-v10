import SwiftUI

struct ContentView: View {
    @State private var vm = PPSRAutomationViewModel()
    @State private var selectedTab: AppTab? = .dashboard
    @State private var selectedCardId: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    nonisolated enum AppTab: String, CaseIterable, Sendable {
        case dashboard, savedCards, workingCards, sessions, settings

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .savedCards: "Cards"
            case .workingCards: "Working"
            case .sessions: "Sessions"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: "bolt.shield.fill"
            case .savedCards: "creditcard.fill"
            case .workingCards: "checkmark.shield.fill"
            case .sessions: "rectangle.stack"
            case .settings: "gearshape.fill"
            }
        }
    }

    private var settingsHash: String {
        "\(vm.appearanceMode.rawValue)-\(vm.testEmail)-\(vm.debugMode)-\(vm.maxConcurrency)-\(vm.useEmailRotation)-\(vm.stealthEnabled)-\(vm.retrySubmitOnFail)-\(vm.autoRetryEnabled)-\(vm.autoRetryMaxAttempts)"
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .tint(.teal)
        .preferredColorScheme(vm.appearanceMode.colorScheme)
        .onChange(of: settingsHash) { _, _ in
            vm.persistSettings()
        }
        .withBatchAlerts(
            showBatchResult: $vm.showBatchResultPopup,
            batchResult: vm.lastBatchResult,
            isRunning: $vm.isRunning,
            onDismissBatch: { vm.showBatchResultPopup = false }
        )
        .keyboardShortcut(shortcuts: true) {
            iPadKeyboardShortcuts
        }
    }

    // MARK: - iPad Three-Column Layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            iPadSidebar
        } content: {
            iPadContentColumn
        } detail: {
            iPadDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var iPadSidebar: some View {
        List(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .navigationTitle("PPSR Solo")
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var iPadContentColumn: some View {
        switch selectedTab ?? .dashboard {
        case .dashboard:
            LoginDashboardView(vm: vm)
                .withPPSRCardNavigation(cards: vm.cards, vm: vm, selectedCardId: $selectedCardId)
        case .savedCards:
            SavedCredentialsView(vm: vm, iPadSelectedCardId: $selectedCardId)
                .withPPSRCardNavigation(cards: vm.cards, vm: vm, selectedCardId: $selectedCardId)
        case .workingCards:
            WorkingLoginsView(vm: vm)
                .withPPSRCardNavigation(cards: vm.cards, vm: vm, selectedCardId: $selectedCardId)
        case .sessions:
            LoginSessionMonitorView(vm: vm)
        case .settings:
            PPSRSettingsView(vm: vm)
        }
    }

    @ViewBuilder
    private var iPadDetailColumn: some View {
        VStack(spacing: 0) {
            iPadQuickActionBar
            Divider()
            if vm.isRunning {
                LiveBatchPanelView(vm: vm, selectedCardId: $selectedCardId)
            } else if let cardId = selectedCardId, let card = vm.cards.first(where: { $0.id == cardId }) {
                PPSRCardDetailView(card: card, vm: vm)
            } else {
                iPadDetailPlaceholder
            }
        }
    }

    private var iPadQuickActionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(vm.isRunning ? .green : .secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(vm.isRunning ? (vm.isPaused ? "Paused" : "Running") : "Idle")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(vm.isRunning ? (vm.isPaused ? .orange : .green) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((vm.isRunning ? (vm.isPaused ? Color.orange : Color.green) : Color.secondary).opacity(0.1))
            .clipShape(Capsule())

            HStack(spacing: 12) {
                iPadQuickStat(value: "\(vm.workingCards.count)", label: "Pass", color: .green)
                iPadQuickStat(value: "\(vm.untestedCards.count)", label: "Queue", color: .secondary)
                iPadQuickStat(value: "\(vm.deadCards.count)", label: "Dead", color: .red)
            }

            Spacer()

            if vm.isRunning {
                if vm.isPaused {
                    Button { vm.resumeQueue() } label: {
                        Image(systemName: "play.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .frame(width: 32, height: 28)
                            .background(Color.green.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                } else {
                    Button { vm.pauseQueue() } label: {
                        Image(systemName: "pause.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 28)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    .disabled(vm.isStopping)
                }
                Button { vm.stopQueue() } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 28)
                        .background(Color.red.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 6))
                }
                .disabled(vm.isStopping)
            } else if !vm.untestedCards.isEmpty {
                Button { vm.testAllUntested() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.caption2)
                        Text("Run").font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.teal)
                    .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func iPadQuickStat(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var iPadDetailPlaceholder: some View {
        ContentUnavailableView {
            Label("Select a Card", systemImage: "creditcard.fill")
        } description: {
            Text("Choose a card from the list to view details, or start a batch to see live progress.")
        }
    }

    // MARK: - iPhone Tab Layout

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "bolt.shield.fill", value: .dashboard) {
                NavigationStack {
                    LoginDashboardView(vm: vm)
                        .withPPSRCardNavigation(cards: vm.cards, vm: vm)
                }
                .withMainMenuButton()
            }

            Tab("Cards", systemImage: "creditcard.fill", value: .savedCards) {
                NavigationStack {
                    SavedCredentialsView(vm: vm)
                        .withPPSRCardNavigation(cards: vm.cards, vm: vm)
                }
                .withMainMenuButton()
            }

            Tab("Working", systemImage: "checkmark.shield.fill", value: .workingCards) {
                NavigationStack {
                    WorkingLoginsView(vm: vm)
                        .withPPSRCardNavigation(cards: vm.cards, vm: vm)
                }
                .withMainMenuButton()
            }

            Tab("Sessions", systemImage: "rectangle.stack", value: .sessions) {
                NavigationStack {
                    LoginSessionMonitorView(vm: vm)
                }
                .withMainMenuButton()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack {
                    PPSRSettingsView(vm: vm)
                }
                .withMainMenuButton()
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var iPadKeyboardShortcuts: some View {
        Button("Run Tests") {
            if !vm.isRunning { vm.testAllUntested() }
        }
        .keyboardShortcut("r", modifiers: .command)

        Button("Import Cards") {
            selectedTab = .savedCards
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("Toggle Pause") {
            if vm.isRunning {
                if vm.isPaused { vm.resumeQueue() } else { vm.pauseQueue() }
            }
        }
        .keyboardShortcut(.space, modifiers: [])

        Button("Stop Batch") {
            if vm.isRunning { vm.stopQueue() }
        }
        .keyboardShortcut(".", modifiers: .command)

        Button("Dashboard") { selectedTab = .dashboard }
            .keyboardShortcut("1", modifiers: .command)
        Button("Cards") { selectedTab = .savedCards }
            .keyboardShortcut("2", modifiers: .command)
        Button("Working") { selectedTab = .workingCards }
            .keyboardShortcut("3", modifiers: .command)
        Button("Sessions") { selectedTab = .sessions }
            .keyboardShortcut("4", modifiers: .command)
        Button("Settings") { selectedTab = .settings }
            .keyboardShortcut("5", modifiers: .command)
    }
}

private struct KeyboardShortcutModifier<Shortcuts: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let shortcuts: () -> Shortcuts

    func body(content: Content) -> some View {
        content
            .background {
                shortcuts()
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func keyboardShortcut<S: View>(shortcuts enabled: Bool, @ViewBuilder content: @escaping () -> S) -> some View {
        modifier(KeyboardShortcutModifier(enabled: enabled, shortcuts: { content() }))
    }
}

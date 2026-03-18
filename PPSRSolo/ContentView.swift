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
        if vm.isRunning {
            LiveBatchPanelView(vm: vm, selectedCardId: $selectedCardId)
        } else if let cardId = selectedCardId, let card = vm.cards.first(where: { $0.id == cardId }) {
            PPSRCardDetailView(card: card, vm: vm)
        } else {
            iPadDetailPlaceholder
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

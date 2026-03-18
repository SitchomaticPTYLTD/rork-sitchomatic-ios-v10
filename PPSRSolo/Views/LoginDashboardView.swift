import SwiftUI

struct LoginDashboardView: View {
    @Bindable var vm: PPSRAutomationViewModel
    @State private var binFilter: String = ""
    @State private var showBINFilter: Bool = false

    private var filteredUntestedCards: [PPSRCard] {
        let cards = vm.untestedCards
        if binFilter.isEmpty { return cards }
        return cards.filter { $0.binPrefix.hasPrefix(binFilter) }
    }

    private var availableQueuedBINs: [String] {
        Set(vm.untestedCards.map(\.binPrefix)).sorted()
    }

    @State private var showStatsPanel: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var maxConcurrencyLimit: Int {
        horizontalSizeClass == .regular ? 16 : 8
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                statusHeader
                if showStatsPanel {
                    lifetimeStatsCard
                }
                if vm.preflightFailed {
                    preflightFailedCard
                }
                if vm.connectionStatus == .error || vm.diagnosticReport != nil {
                    connectionDiagnosticsCard
                }
                if vm.isRunning {
                    batchProgressCard
                    queueControls
                }
                if vm.stealthEnabled {
                    stealthBadge
                }
                testControlsCard
                statsRow
                if !vm.untestedCards.isEmpty {
                    queuedCardsSection
                }
                if !vm.testingCards.isEmpty {
                    cardSection(title: "Testing Now", cards: vm.testingCards, color: .teal, icon: "arrow.triangle.2.circlepath")
                }
                if !vm.deadCards.isEmpty {
                    deadCardsSection
                }
                if vm.cards.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .refreshable {
            await vm.testConnection()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(.snappy) { showStatsPanel.toggle() } } label: {
                    Image(systemName: showStatsPanel ? "chart.bar.fill" : "chart.bar")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(.snappy) { showBINFilter.toggle() } } label: {
                    Image(systemName: showBINFilter ? "number.circle.fill" : "number.circle")
                }
            }
        }
        .task {
            await vm.testConnection()
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(.teal)
                .symbolEffect(.pulse, isActive: vm.isRunning)

            VStack(alignment: .leading, spacing: 2) {
                Text("PPSR TestFlow")
                    .font(.title3.bold())
                Text("transact.ppsr.gov.au")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            connectionBadge
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var connectionBadge: some View {
        Button {
            Task { await vm.testConnection() }
        } label: {
            HStack(spacing: 4) {
                if vm.connectionStatus == .connecting || vm.isDiagnosticRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                }
                Text(vm.connectionStatus == .connecting ? "Testing..." : vm.connectionStatus.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(connectionColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(connectionColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .sensoryFeedback(.impact(weight: .light), trigger: vm.connectionStatus.rawValue)
    }

    private var connectionColor: Color {
        switch vm.connectionStatus {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .secondary
        case .error: .red
        }
    }

    private var stealthBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.caption)
                .foregroundStyle(.purple)
            Text("Ultra Stealth Mode")
                .font(.caption.bold())
                .foregroundStyle(.purple)
            Spacer()
            Text("Rotating UA + Fingerprints")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var batchProgressCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.teal.opacity(0.15), lineWidth: 6)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: vm.batchProgress)
                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: vm.batchProgress)
                    VStack(spacing: 0) {
                        Text("\(Int(vm.batchProgress * 100))")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundStyle(.teal)
                            .contentTransition(.numericText(value: vm.batchProgress))
                            .animation(.snappy, value: vm.batchCompletedCards)
                        Text("%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.teal.opacity(0.6))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Batch Testing")
                            .font(.subheadline.bold())
                            .foregroundStyle(.teal)
                        batchConnectivityDot
                        if vm.isPaused {
                            Text(vm.pauseCountdown > 0 ? "PAUSED \(vm.pauseCountdown)s" : "PAUSED")
                                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                                .contentTransition(.numericText(value: Double(vm.pauseCountdown)))
                                .animation(.snappy, value: vm.pauseCountdown)
                        }
                        if vm.isStopping {
                            Text("STOPPING")
                                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        Text("\(vm.batchCompletedCards)")
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .contentTransition(.numericText(value: Double(vm.batchCompletedCards)))
                            .animation(.snappy, value: vm.batchCompletedCards)
                        Text("/")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(vm.batchTotalCards)")
                            .font(.system(.subheadline, design: .monospaced, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("cards")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        Text("\(vm.activeTestCount) active")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("\(vm.untestedCards.count) queued")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            HStack(spacing: 6) {
                batchLiveCounter(value: vm.batchWorkingLive, label: "Pass", color: .green)
                batchLiveCounter(value: vm.batchDeadLive, label: "Fail", color: .red)
                batchLiveCounter(value: vm.batchRequeuedLive, label: "Retry", color: .orange)
            }

            HStack(spacing: 0) {
                batchMetric(
                    icon: "clock",
                    value: formatElapsed(vm.batchElapsedSeconds),
                    label: "Elapsed"
                )
                Spacer()
                batchMetric(
                    icon: "gauge.with.dots.needle.33percent",
                    value: String(format: "%.1f/min", vm.batchCardsPerMinute),
                    label: "Speed"
                )
                Spacer()
                batchMetric(
                    icon: "hourglass",
                    value: vm.batchEstimatedSecondsRemaining > 0 ? formatElapsed(vm.batchEstimatedSecondsRemaining) : "--",
                    label: "ETA"
                )
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private func batchLiveCounter(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)")
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func batchMetric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.teal.opacity(0.7))
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var queueControls: some View {
        HStack(spacing: 10) {
            if vm.isPaused {
                Button {
                    vm.resumeQueue()
                } label: {
                    VStack(spacing: 4) {
                        Label("Resume Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                        if vm.pauseCountdown > 0 {
                            Text("Auto-resume in \(vm.pauseCountdown)s")
                                .font(.system(.caption2, design: .monospaced))
                                .contentTransition(.numericText(value: Double(vm.pauseCountdown)))
                                .animation(.snappy, value: vm.pauseCountdown)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(.rect(cornerRadius: 12))
                }
            } else {
                Button {
                    vm.pauseQueue()
                } label: {
                    Label("Pause 60s", systemImage: "pause.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(vm.isStopping)
            }

            Button {
                vm.stopQueue()
            } label: {
                VStack(spacing: 4) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.bold())
                    Text("Finish current batch")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(vm.isStopping)
            .sensoryFeedback(.warning, trigger: vm.isStopping)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            MiniStat(value: "\(vm.workingCards.count)", label: "Working", color: .green, icon: "checkmark.circle.fill")
            MiniStat(value: "\(vm.untestedCards.count)", label: "Queued", color: .secondary, icon: "clock")
            MiniStat(value: "\(vm.deadCards.count)", label: "Dead", color: .red, icon: "xmark.circle.fill")
            MiniStat(value: "\(vm.cards.count)", label: "Total", color: .blue, icon: "creditcard.fill")
        }
    }

    private var queuedCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Queued \u{2014} Untested")
                    .font(.headline)
                Spacer()
                Text("\(filteredUntestedCards.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }

            if showBINFilter {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "number").foregroundStyle(.teal)
                        TextField("Filter by BIN", text: $binFilter)
                            .font(.system(.body, design: .monospaced))
                            .keyboardType(.numberPad)
                        if !binFilter.isEmpty {
                            Button { withAnimation(.snappy) { binFilter = "" } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10))

                    if !availableQueuedBINs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                FilterChipSmall(title: "All", isSelected: binFilter.isEmpty) {
                                    withAnimation(.snappy) { binFilter = "" }
                                }
                                ForEach(availableQueuedBINs, id: \.self) { bin in
                                    FilterChipSmall(title: bin, isSelected: binFilter == bin) {
                                        withAnimation(.snappy) { binFilter = bin }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ForEach(Array(filteredUntestedCards.prefix(50))) { card in
                NavigationLink(value: card.id) {
                    CardRow(card: card, accentColor: .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cardSection(title: String, cards: [PPSRCard], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(color)
            }

            ForEach(cards) { card in
                NavigationLink(value: card.id) {
                    CardRow(card: card, accentColor: color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var deadCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text("Dead Cards")
                    .font(.headline)
                Spacer()
                Text("\(vm.deadCards.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.red)

                Button {
                    vm.purgeDeadCards()
                } label: {
                    Text("Purge All")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }

            ForEach(vm.deadCards) { card in
                NavigationLink(value: card.id) {
                    CardRow(card: card, accentColor: .red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectionDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: vm.connectionStatus == .error ? "exclamationmark.triangle.fill" : "stethoscope")
                    .font(.title3)
                    .foregroundStyle(vm.connectionStatus == .error ? .red : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.connectionStatus == .error ? "Connection Issue Detected" : "Connection Diagnostics")
                        .font(.subheadline.bold())
                    if let health = vm.lastHealthCheck {
                        Text(health.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if vm.isDiagnosticRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let report = vm.diagnosticReport {
                VStack(spacing: 6) {
                    ForEach(report.steps) { step in
                        HStack(spacing: 8) {
                            Image(systemName: stepIcon(step.status))
                                .font(.caption)
                                .foregroundStyle(stepColor(step.status))
                                .frame(width: 16)
                            Text(step.name)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .frame(width: 110, alignment: .leading)
                            Text(step.detail)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            if let ms = step.latencyMs {
                                Text("\(ms)ms")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Text(report.recommendation)
                    .font(.caption)
                    .foregroundStyle(report.overallHealthy ? .green : .orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((report.overallHealthy ? Color.green : Color.orange).opacity(0.08))
                    .clipShape(.rect(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.runFullDiagnostic() }
                } label: {
                    Label(vm.isDiagnosticRunning ? "Running..." : "Run Diagnostics", systemImage: "stethoscope")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .disabled(vm.isDiagnosticRunning)

                Button {
                    Task { await vm.testConnection() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .disabled(vm.connectionStatus == .connecting)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private func stepIcon(_ status: DiagnosticStep.StepStatus) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .running: "arrow.triangle.2.circlepath"
        case .pending: "circle"
        }
    }

    private func stepColor(_ status: DiagnosticStep.StepStatus) -> Color {
        switch status {
        case .passed: .green
        case .failed: .red
        case .warning: .orange
        case .running: .blue
        case .pending: .secondary
        }
    }

    @ViewBuilder
    private var batchConnectivityDot: some View {
        if vm.isRunning {
            let color: Color = {
                switch vm.batchConnectivityHealth {
                case .healthy: return .green
                case .degraded: return .yellow
                case .down: return .red
                }
            }()
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 3)
        }
    }

    private var preflightFailedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Batch Check Failed")
                        .font(.subheadline.bold())
                    Text(vm.preflightMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    vm.preflightFailed = false
                    Task { await vm.testConnection() }
                } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(.rect(cornerRadius: 10))
                }

                Button {
                    vm.preflightFailed = false
                    Task { await vm.testAllDNS() }
                } label: {
                    Label("Test DNS", systemImage: "bolt.horizontal.circle")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(.rect(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var testControlsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
                Text("Sessions")
                    .font(.subheadline.bold())
                Spacer()
                Picker("", selection: $vm.maxConcurrency) {
                    ForEach(1...maxConcurrencyLimit, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .tint(.teal)
            }

            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
                Text("Test Order")
                    .font(.subheadline.bold())
                Spacer()
                Menu {
                    ForEach(PPSRAutomationViewModel.CardSortOption.allCases) { option in
                        Button {
                            withAnimation(.snappy) {
                                if vm.cardSortOption == option { vm.cardSortAscending.toggle() }
                                else { vm.cardSortOption = option; vm.cardSortAscending = false }
                            }
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if vm.cardSortOption == option {
                                    Image(systemName: vm.cardSortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.cardSortOption.rawValue)
                            .font(.subheadline.weight(.medium))
                        Image(systemName: vm.cardSortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.teal)
                }
            }

            if !vm.untestedCards.isEmpty && !vm.isRunning {
                Button {
                    vm.testAllUntested()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Test All Untested (\(vm.untestedCards.count))")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.teal)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: vm.isRunning)
            }
        }
        .sensoryFeedback(.success, trigger: vm.workingCards.count)
        .sensoryFeedback(.error, trigger: vm.deadCards.count)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var lifetimeStatsCard: some View {
        let stats = vm.statsService
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
                Text("Lifetime Statistics")
                    .font(.headline)
                Spacer()
                Text("\(stats.totalBatches) batches")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                LifetimeStatPill(value: "\(stats.lifetimeTested)", label: "Tested", color: .blue)
                LifetimeStatPill(value: "\(stats.lifetimeWorking)", label: "Working", color: .green)
                LifetimeStatPill(value: "\(stats.lifetimeDead)", label: "Dead", color: .red)
            }

            HStack(spacing: 8) {
                LifetimeStatPill(value: String(format: "%.0f%%", stats.lifetimeSuccessRate * 100), label: "Success Rate", color: stats.lifetimeSuccessRate >= 0.5 ? .green : .orange)
                LifetimeStatPill(value: String(format: "%.1fs", stats.averageTestDuration), label: "Avg Duration", color: .purple)
                LifetimeStatPill(value: "\(stats.testsToday)", label: "Today", color: .teal)
            }

            if !stats.last7DaysCounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 7 Days")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(stats.last7DaysCounts, id: \.day) { item in
                            VStack(spacing: 4) {
                                let maxCount = max(stats.last7DaysCounts.map(\.count).max() ?? 1, 1)
                                let barHeight = max(4, CGFloat(item.count) / CGFloat(maxCount) * 40)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(item.count > 0 ? Color.teal : Color(.tertiarySystemFill))
                                    .frame(height: barHeight)
                                Text(item.day)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 56)
                }
            }

            HStack(spacing: 6) {
                Text(String(format: "%.1f cards/day avg", stats.averageTestsPerDay))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.lifetimeRequeued) requeued lifetime")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.teal.opacity(0.5))
                .symbolEffect(.pulse.byLayer, options: .repeating)
            Text("No Cards Added")
                .font(.title3.bold())
            Text("Go to Cards tab to import.\nSupports many formats automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct LifetimeStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct MiniStat: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct CardRow: View {
    let card: PPSRCard
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(brandColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: card.brand.iconName)
                    .font(.title3)
                    .foregroundStyle(brandColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.brand.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(card.number)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(card.formattedExpiry)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if card.totalTests > 0 {
                        Text("\(card.successCount)/\(card.totalTests) passed")
                            .font(.caption2)
                            .foregroundStyle(card.status == .working ? .green : .red)
                    }
                }
            }

            Spacer()

            if card.status == .testing {
                ProgressView()
                    .tint(.teal)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var brandColor: Color {
        switch card.brand {
        case .visa: .blue
        case .mastercard: .orange
        case .amex: .green
        case .jcb: .red
        case .discover: .purple
        case .dinersClub: .indigo
        case .unionPay: .teal
        case .unknown: .secondary
        }
    }
}

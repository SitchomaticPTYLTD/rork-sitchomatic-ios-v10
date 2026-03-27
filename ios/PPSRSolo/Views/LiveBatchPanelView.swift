import SwiftUI

struct LiveBatchPanelView: View {
    let vm: PPSRAutomationViewModel
    @Binding var selectedCardId: String?
    @State private var showLogOnly: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            batchHeader
            Divider()
            progressSection
            Divider()
            liveCounters
            Divider()
            metricsRow
            Divider()
            controlsBar
            Divider()
            logSection
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Batch")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var batchHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.teal.opacity(0.15), lineWidth: 5)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: vm.batchProgress)
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.5), value: vm.batchProgress)
                Text("\(Int(vm.batchProgress * 100))%")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.teal)
                    .contentTransition(.numericText(value: vm.batchProgress))
                    .animation(.snappy, value: vm.batchCompletedCards)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Batch Testing")
                        .font(.subheadline.bold())
                        .foregroundStyle(.teal)
                    connectivityDot
                    if vm.isPaused {
                        pauseBadge
                    }
                    if vm.isStopping {
                        Text("STOPPING")
                            .font(.system(.caption2, design: .monospaced, weight: .heavy))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15)).clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text("\(vm.batchCompletedCards)")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .contentTransition(.numericText(value: Double(vm.batchCompletedCards)))
                        .animation(.snappy, value: vm.batchCompletedCards)
                    Text("/ \(vm.batchTotalCards) cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(vm.activeTestCount) active")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var progressSection: some View {
        ProgressView(value: vm.batchProgress)
            .tint(.teal)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private var liveCounters: some View {
        HStack(spacing: 6) {
            liveCounter(value: vm.batchWorkingLive, label: "Pass", color: .green)
            liveCounter(value: vm.batchDeadLive, label: "Fail", color: .red)
            liveCounter(value: vm.batchRequeuedLive, label: "Retry", color: .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func liveCounter(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
    }

    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricItem(icon: "clock", value: formatElapsed(vm.batchElapsedSeconds), label: "Elapsed")
            metricItem(icon: "gauge.with.dots.needle.33percent", value: String(format: "%.1f/m", vm.batchCardsPerMinute), label: "Speed")
            metricItem(icon: "hourglass", value: vm.batchEstimatedSecondsRemaining > 0 ? formatElapsed(vm.batchEstimatedSecondsRemaining) : "--", label: "ETA")
        }
        .padding(.vertical, 8)
    }

    private func metricItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.teal.opacity(0.7))
            Text(value)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            if vm.isPaused {
                Button { vm.resumeQueue() } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(.rect(cornerRadius: 8))
                }
            } else {
                Button { vm.pauseQueue() } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .disabled(vm.isStopping)
            }

            Button { vm.stopQueue() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .disabled(vm.isStopping)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Log")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vm.globalLogs.count) entries")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.globalLogs.prefix(200)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.formattedTime)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 58, alignment: .leading)
                            Circle()
                                .fill(logColor(entry.level))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(entry.message)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(logColor(entry.level).opacity(0.9))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var connectivityDot: some View {
        let color: Color = {
            switch vm.batchConnectivityHealth {
            case .healthy: return .green
            case .degraded: return .yellow
            case .down: return .red
            }
        }()
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .shadow(color: color.opacity(0.6), radius: 2)
    }

    @ViewBuilder
    private var pauseBadge: some View {
        Text(vm.pauseCountdown > 0 ? "PAUSED \(vm.pauseCountdown)s" : "PAUSED")
            .font(.system(.caption2, design: .monospaced, weight: .heavy))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.15)).clipShape(Capsule())
            .contentTransition(.numericText(value: Double(vm.pauseCountdown)))
            .animation(.snappy, value: vm.pauseCountdown)
    }

    private func logColor(_ level: PPSRLogEntry.Level) -> Color {
        switch level {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

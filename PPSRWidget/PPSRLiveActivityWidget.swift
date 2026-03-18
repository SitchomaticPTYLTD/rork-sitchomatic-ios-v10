import ActivityKit
import SwiftUI
import WidgetKit

struct PPSRLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PPSRActivityAttributes.self) { context in
            PPSRLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Working", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("\(context.state.workingCount)")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("Dead", systemImage: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("\(context.state.deadCount)")
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if context.state.isFinished {
                            Text(context.state.wasStopped ? "Batch Stopped" : "Batch Complete")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("PPSR Batch")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        Text("\(context.state.completedCards)/\(context.state.totalCards)")
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: progress(context.state))
                            .tint(progressTint(context.state))

                        HStack {
                            if context.state.isFinished {
                                Label(formatDuration(context.state.elapsedSeconds), systemImage: "clock")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(formatDuration(context.state.elapsedSeconds), systemImage: "clock")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if context.state.requeuedCount > 0 {
                                    Label("\(context.state.requeuedCount)", systemImage: "arrow.uturn.backward")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }

                                Spacer()

                                if context.state.cardsPerMinute > 0 {
                                    Label(String(format: "%.1f/min", context.state.cardsPerMinute), systemImage: "gauge.high")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress(context.state))
                        .stroke(progressTint(context.state), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: context.state.isFinished ? "checkmark" : "doc.text.magnifyingglass")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(progressTint(context.state))
                }
                .frame(width: 20, height: 20)
            } compactTrailing: {
                Text("\(context.state.completedCards)/\(context.state.totalCards)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(progressTint(context.state))
                    .contentTransition(.numericText())
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress(context.state))
                        .stroke(progressTint(context.state), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
            }
        }
    }

    private func progress(_ state: PPSRActivityAttributes.ContentState) -> Double {
        guard state.totalCards > 0 else { return 0 }
        return Double(state.completedCards) / Double(state.totalCards)
    }

    private func progressTint(_ state: PPSRActivityAttributes.ContentState) -> Color {
        if state.isFinished {
            return state.wasStopped ? .orange : .green
        }
        return .teal
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct PPSRLockScreenView: View {
    let context: ActivityViewContext<PPSRActivityAttributes>

    private var progress: Double {
        guard context.state.totalCards > 0 else { return 0 }
        return Double(context.state.completedCards) / Double(context.state.totalCards)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3.bold())
                    .foregroundStyle(.teal)
                Text(context.state.isFinished ? (context.state.wasStopped ? "Batch Stopped" : "Batch Complete") : "PPSR Batch Running")
                    .font(.headline)
                Spacer()
                Text("\(context.state.completedCards)/\(context.state.totalCards)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }

            ProgressView(value: progress)
                .tint(context.state.isFinished ? (context.state.wasStopped ? .orange : .green) : .teal)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("\(context.state.workingCount)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }

                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("\(context.state.deadCount)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("\(context.state.requeuedCount)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText())
                }

                Spacer()

                if !context.state.isFinished, context.state.cardsPerMinute > 0 {
                    Text(String(format: "%.1f/min", context.state.cardsPerMinute))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(formatDuration(context.state.elapsedSeconds))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.75))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

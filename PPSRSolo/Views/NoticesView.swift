import SwiftUI

struct NoticesView: View {
    private let service = NoticesService.shared

    var body: some View {
        List {
            if service.notices.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("All Clear")
                            .font(.headline)
                        Text("No notices or failures recorded.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section {
                    ForEach(service.notices) { notice in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(notice.isRead ? Color.clear : Color.orange)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: sourceIcon(notice.source))
                                        .font(.caption)
                                        .foregroundStyle(sourceColor(notice.source))
                                    Text(sourceLabel(notice.source))
                                        .font(.caption2.bold())
                                        .foregroundStyle(sourceColor(notice.source))
                                    if notice.autoRetried {
                                        Text("Auto-Retried")
                                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.mint, in: Capsule())
                                    }
                                }
                                Text(notice.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(DateFormatters.mediumDateTime.string(from: notice.date))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("\(service.notices.count) Notices")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { service.markAllRead() } label: {
                        Label("Mark All Read", systemImage: "envelope.open")
                    }
                    Button(role: .destructive) { service.clearAll() } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(service.notices.isEmpty)
            }
        }
        .onAppear { service.markAllRead() }
    }

    private func sourceIcon(_ source: NoticeSource) -> String {
        switch source {
        case .ppsr: "doc.text.magnifyingglass"
        case .proxy: "network"
        case .general: "info.circle"
        }
    }

    private func sourceColor(_ source: NoticeSource) -> Color {
        switch source {
        case .ppsr: .orange
        case .proxy: .blue
        case .general: .secondary
        }
    }

    private func sourceLabel(_ source: NoticeSource) -> String {
        switch source {
        case .ppsr: "PPSR"
        case .proxy: "Proxy"
        case .general: "General"
        }
    }
}

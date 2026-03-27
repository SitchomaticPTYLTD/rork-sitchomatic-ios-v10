import SwiftUI

struct PPSRCardDetailView: View {
    let card: PPSRCard
    let vm: PPSRAutomationViewModel
    @State private var copiedLabel: String = ""
    @State private var showCopiedToast: Bool = false
    @State private var statusGlow: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                cardHeader
                quickCopySection
                if !card.testResults.isEmpty { miniHistoryChart }
                binDataSection
                statsSection
                actionsSection
                if !card.testResults.isEmpty { testHistorySection }
                infoSection
            }
            .listStyle(.insetGrouped)

            if showCopiedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(copiedLabel)
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.green.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(card.number)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if card.binData == nil { await card.loadBINData() }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                statusGlow = true
            }
        }
    }

    private var cardHeader: some View {
        Section {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: brandColor.opacity(0.9), location: 0),
                                    .init(color: brandColor.opacity(0.65), location: 0.5),
                                    .init(color: brandColorSecondary.opacity(0.5), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 190)
                        .shadow(color: brandColor.opacity(0.25), radius: 12, y: 6)

                    if card.status == .testing {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(statusGlow ? 0.06 : 0.0))
                            .frame(height: 190)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: card.brand.iconName)
                                .font(.title)
                                .foregroundStyle(.white)
                            Spacer()
                            statusBadge
                        }

                        Text(formattedCardNumber)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.white)
                            .tracking(2)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXPIRES").font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                Text(card.formattedExpiry).font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(.white)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("CVV").font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                Text(card.cvv).font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(20)
                }
                .contextMenu {
                    Button { copyToClipboard(card.pipeFormat, label: "Pipe format copied") } label: {
                        Label("Copy Pipe Format", systemImage: "doc.on.doc")
                    }
                    Button { copyToClipboard(card.number, label: "Card number copied") } label: {
                        Label("Copy Number", systemImage: "number")
                    }
                    Button { copyToClipboard("\(card.number)|\(card.formattedExpiry)|\(card.cvv)", label: "Full card copied") } label: {
                        Label("Copy Full Card", systemImage: "creditcard")
                    }
                    Divider()
                    ShareLink(item: card.pipeFormat) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 5) {
            switch card.status {
            case .working:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .symbolEffect(.bounce, value: card.status)
            case .testing:
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            case .dead:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .untested:
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
            }
            Text(card.status.rawValue).font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var quickCopySection: some View {
        Section {
            HStack(spacing: 10) {
                quickCopyButton(label: "Number", value: card.number, icon: "number", toastLabel: "Card number copied")
                quickCopyButton(label: "Pipe", value: card.pipeFormat, icon: "rectangle.split.3x1", toastLabel: "Pipe format copied")
                quickCopyButton(label: "BIN", value: card.binPrefix, icon: "barcode", toastLabel: "BIN copied")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func quickCopyButton(label: String, value: String, icon: String, toastLabel: String) -> some View {
        Button {
            copyToClipboard(value, label: toastLabel)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.teal)
                Text(label)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.teal.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: showCopiedToast)
    }

    @ViewBuilder
    private var miniHistoryChart: some View {
        let recentResults = Array(card.testResults.prefix(10))
        if !recentResults.isEmpty {
            Section("Recent Results") {
                HStack(spacing: 3) {
                    ForEach(recentResults.reversed()) { result in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(result.success ? Color.green : Color.red)
                            .frame(height: result.success ? 28 : 18)
                            .frame(maxWidth: .infinity)
                    }
                    if recentResults.count < 10 {
                        ForEach(0..<(10 - recentResults.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 10)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 32, alignment: .bottom)
                .padding(.vertical, 4)

                HStack {
                    Text("Last \(recentResults.count) tests")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    let passCount = recentResults.filter(\.success).count
                    Text("\(passCount)/\(recentResults.count) passed")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(passCount > recentResults.count / 2 ? .green : .red)
                }
            }
        }
    }

    @ViewBuilder
    private var binDataSection: some View {
        if let binData = card.binData, binData.isLoaded {
            Section("BIN Information") {
                LabeledContent("BIN") { Text(card.binPrefix).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                if !binData.scheme.isEmpty { LabeledContent("Scheme", value: binData.scheme) }
                if !binData.type.isEmpty { LabeledContent("Type", value: binData.type.capitalized) }
                if !binData.category.isEmpty { LabeledContent("Category", value: binData.category.capitalized) }
                if !binData.issuer.isEmpty { LabeledContent("Issuer", value: binData.issuer) }
                if !binData.country.isEmpty {
                    LabeledContent("Country") {
                        HStack(spacing: 4) {
                            if !binData.countryCode.isEmpty { Text(flagEmoji(for: binData.countryCode)) }
                            Text(binData.country)
                        }
                    }
                }
            }
        } else {
            Section("BIN Information") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading BIN data...").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsSection: some View {
        Section("Performance") {
            HStack {
                StatItem(value: "\(card.totalTests)", label: "Total Tests", color: .blue)
                StatItem(value: "\(card.successCount)", label: "Passed", color: .green)
                StatItem(value: "\(card.failureCount)", label: "Failed", color: .red)
            }
            if card.totalTests > 0 {
                LabeledContent("Success Rate") {
                    Text(String(format: "%.0f%%", card.successRate * 100))
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .foregroundStyle(card.successRate >= 0.5 ? .green : .red)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                vm.testSingleCard(card)
            } label: {
                HStack {
                    Spacer()
                    Label("Run PPSR Test", systemImage: "play.fill").font(.headline)
                    Spacer()
                }
            }
            .disabled(card.status == .testing)
            .listRowBackground(card.status == .testing ? Color.teal.opacity(0.3) : Color.teal)
            .foregroundStyle(.white)

            if card.status == .dead {
                Button { vm.restoreCard(card) } label: { Label("Restore Card", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { vm.deleteCard(card) } label: { Label("Delete Permanently", systemImage: "trash") }
            }
        }
    }

    private var testHistorySection: some View {
        Section("Test History") {
            ForEach(card.testResults) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(result.success ? "Passed" : "Failed").font(.subheadline.bold()).foregroundStyle(result.success ? .green : .red)
                            Text(result.formattedDuration).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(result.formattedDate).font(.caption).foregroundStyle(.tertiary)
                        if let err = result.errorMessage {
                            Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var infoSection: some View {
        Section("Card Info") {
            LabeledContent("Brand", value: card.brand.rawValue)
            LabeledContent("Number") { Text(card.number).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
            LabeledContent("Expiry", value: card.formattedExpiry)
            LabeledContent("CVV", value: card.cvv)
            LabeledContent("Pipe Format") { Text(card.pipeFormat).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }
            LabeledContent("Added") { Text(card.addedAt, style: .date) }
            if let lastTest = card.lastTestedAt {
                LabeledContent("Last Tested") { Text(lastTest, style: .relative).foregroundStyle(.secondary) }
            }
        }
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
        case .unknown: .gray
        }
    }

    private var brandColorSecondary: Color {
        switch card.brand {
        case .visa: .cyan
        case .mastercard: .yellow
        case .amex: .mint
        case .jcb: .pink
        case .discover: .indigo
        case .dinersClub: .purple
        case .unionPay: .cyan
        case .unknown: Color(.systemGray4)
        }
    }

    private var formattedCardNumber: String {
        let num = card.number
        var groups: [String] = []
        var index = num.startIndex
        let groupSize = card.brand == .amex ? [4, 6, 5] : [4, 4, 4, 4]
        for size in groupSize {
            let end = num.index(index, offsetBy: min(size, num.distance(from: index, to: num.endIndex)))
            groups.append(String(num[index..<end]))
            index = end
            if index >= num.endIndex { break }
        }
        return groups.joined(separator: " ")
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value).map { String($0) }
        }.joined()
    }

    private func copyToClipboard(_ value: String, label: String) {
        UIPasteboard.general.string = value
        copiedLabel = label
        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedToast = false }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

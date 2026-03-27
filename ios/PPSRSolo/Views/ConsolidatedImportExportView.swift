import SwiftUI
import UniformTypeIdentifiers

struct ConsolidatedImportExportView: View {
    private let exportService = AppDataExportService.shared
    @State private var exportedJSON: String = ""
    @State private var showShareSheet: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var importResult: AppDataExportService.ImportResult?
    @State private var showResultAlert: Bool = false

    var body: some View {
        List {
            exportSection
            importSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Import / Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) { shareSheet }
        .sheet(isPresented: $showImportSheet) { importSheet }
        .alert("Import Complete", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importResult?.summary ?? "Nothing imported")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                exportedJSON = exportService.exportJSON()
                showShareSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.title3).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export All Data").font(.subheadline.bold())
                        Text("Settings, cards, proxies, VPN, DNS, emails, keys")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Button {
                UIPasteboard.general.string = exportService.exportJSON()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title3).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy to Clipboard").font(.subheadline.bold())
                        Text("Copy full JSON backup to clipboard")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Exports all app data as a JSON file for backup or transfer to another device.")
        }
    }

    private var importSection: some View {
        Section {
            Button { showImportSheet = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.title3).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from JSON").font(.subheadline.bold())
                        Text("Paste or load a backup to restore data")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Button {
                guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
                let result = exportService.importJSON(text)
                importResult = result
                showResultAlert = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.title3).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Clipboard").font(.subheadline.bold())
                        Text("Import JSON data currently in clipboard")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Imported data is merged with existing data. Cards with duplicate numbers are skipped.")
        }
    }

    private var shareSheet: some View {
        ShareSheetView(items: [exportedJSON])
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import JSON Backup").font(.headline)
                    Text("Paste the full JSON export content below.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $importText)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Color(.tertiarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 10))
                    .frame(minHeight: 200)
                Spacer()
            }
            .padding()
            .navigationTitle("Import").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showImportSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let result = exportService.importJSON(importText)
                        importResult = result
                        importText = ""
                        showImportSheet = false
                        showResultAlert = true
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}

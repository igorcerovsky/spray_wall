import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @State private var exportedJSON = ""
    @State private var importJSON = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = appModel.currentUser {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                    }

                    Button("Sign Out", role: .destructive) {
                        appModel.logout()
                    }
                }

                Section("Data Export") {
                    Button("Generate JSON Export") {
                        exportJSON()
                    }
                    .buttonStyle(.borderedProminent)

                    if !exportedJSON.isEmpty {
                        TextEditor(text: $exportedJSON)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 140)
#if os(iOS)
                        Button("Copy Export to Clipboard") {
                            UIPasteboard.general.string = exportedJSON
                            appModel.globalMessage = "Export copied to clipboard."
                        }
#endif
                    }
                }

                Section("Data Import") {
                    TextEditor(text: $importJSON)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 140)

                    Button("Import JSON") {
                        importArchive()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func exportJSON() {
        do {
            exportedJSON = try ProjectArchiveService.exportJSON(context: modelContext)
            appModel.globalMessage = "Export generated."
        } catch {
            appModel.globalMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importArchive() {
        let cleaned = importJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            appModel.globalMessage = "Paste JSON first."
            return
        }

        do {
            try ProjectArchiveService.importJSON(cleaned, context: modelContext)
            appModel.globalMessage = "Import complete."
        } catch {
            appModel.globalMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

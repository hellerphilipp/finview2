import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// File-menu command to export the whole ledger to a portable SQLite database.
struct ExportCommands: Commands {
    let context: ModelContext

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Database…") { export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    @MainActor
    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export Database"
        panel.canCreateDirectories = true
        // The extension comes from allowedContentTypes; don't repeat it in the name.
        if let type = UTType(filenameExtension: "tallydb") {
            panel.allowedContentTypes = [type]
            panel.nameFieldStringValue = "Tally Export"
        } else {
            panel.nameFieldStringValue = "Tally Export.tallydb"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            try ExportService.writeSQLite(to: url, accounts: accounts, transactions: transactions)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = String(describing: error)
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

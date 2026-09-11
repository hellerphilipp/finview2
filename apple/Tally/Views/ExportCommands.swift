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
        panel.nameFieldStringValue = "Tally Export.sqlite"
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: "sqlite") { panel.allowedContentTypes = [type] }

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

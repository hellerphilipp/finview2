import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ImportKit

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var selectedAccountID: PersistentIdentifier?
    @State private var showingFileImporter = false
    @State private var fileName = ""
    @State private var previewRows: [PreviewRow] = []
    @State private var classification: ImportService.PreviewResult?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var selectedAccount: Account? {
        accounts.first { $0.persistentModelID == selectedAccountID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            content
        }
        .navigationTitle("Import")
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                      allowsMultipleSelection: false,
                      onCompletion: handleFile)
        .onAppear {
            if selectedAccountID == nil { selectedAccountID = accounts.first?.persistentModelID }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Account", selection: $selectedAccountID) {
                Text("Select…").tag(Optional<PersistentIdentifier>.none)
                ForEach(accounts) { Text($0.name).tag(Optional($0.persistentModelID)) }
            }
            .frame(maxWidth: 260)

            Button {
                showingFileImporter = true
            } label: {
                Label("Choose CSV…", systemImage: "doc.badge.plus")
            }
            .disabled(selectedAccount?.importProfile == nil)

            if !fileName.isEmpty {
                Text(fileName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()

            if let c = classification, !previewRows.isEmpty {
                Button {
                    commit()
                } label: {
                    Label("Import \(c.newCount) New", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(c.newCount == 0)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let selectedAccount, selectedAccount.importProfile == nil {
            notice("This account has no import profile. Assign one in Accounts.",
                   systemImage: "exclamationmark.triangle", tint: .orange)
        } else if let errorMessage {
            notice(errorMessage, systemImage: "xmark.octagon", tint: .red)
        } else if let successMessage, previewRows.isEmpty {
            notice(successMessage, systemImage: "checkmark.circle", tint: .green)
        } else if previewRows.isEmpty {
            notice("Choose a CSV statement to preview transactions before importing.",
                   systemImage: "square.and.arrow.down")
        } else {
            previewTable
        }
    }

    private var previewTable: some View {
        let currency = selectedAccount?.currencyCode ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            if let c = classification {
                HStack(spacing: 16) {
                    Text("\(c.rows.count) rows").bold()
                    Label("\(c.newCount) new", systemImage: "plus.circle").foregroundStyle(.green)
                    if c.duplicateCount > 0 {
                        Label("\(c.duplicateCount) already imported", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Table(previewRows) {
                TableColumn("Date") { Text(DateText.string($0.row.date)) }
                TableColumn("Description") { Text($0.row.description) }
                TableColumn("Amount") { r in
                    Text(Money.string(r.row.amount, currency: currency))
                        .foregroundStyle(r.row.amount < 0 ? Color.primary : Color.green)
                        .monospacedDigit()
                }
                TableColumn("Original") { r in
                    if r.row.originalCurrency != currency && !r.row.originalCurrency.isEmpty {
                        Text(Money.string(r.row.originalAmount, currency: r.row.originalCurrency))
                            .foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                TableColumn("Status") { r in
                    r.isDuplicate
                        ? Text("Duplicate").foregroundStyle(.secondary)
                        : Text("New").foregroundStyle(.green)
                }
            }
        }
    }

    private func notice(_ text: String, systemImage: String, tint: Color = .secondary) -> some View {
        ContentUnavailableView {
            Label(text, systemImage: systemImage)
        }
        .foregroundStyle(tint == .secondary ? .secondary : tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func handleFile(_ result: Result<[URL], Error>) {
        errorMessage = nil
        successMessage = nil
        do {
            guard let url = try result.get().first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            guard let account = selectedAccount, let profile = account.importProfile else {
                errorMessage = "Select an account with an import profile first."
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = try ImportService.preview(csvText: text, profileYAML: profile.specYAML)
            let existing = existingFingerprints(for: account)

            fileName = url.lastPathComponent
            previewRows = rows.map { row in
                PreviewRow(row: row,
                           isDuplicate: existing.contains(ImportService.fingerprint(accountID: account.id, row: row)))
            }
            classification = ImportService.classify(rows: rows, account: account, in: context)
        } catch {
            errorMessage = "Could not import: \(error.localizedDescription)"
            previewRows = []
            classification = nil
        }
    }

    private func commit() {
        guard let account = selectedAccount else { return }
        do {
            let rows = previewRows.map(\.row)
            let batch = try ImportService.commit(rows: rows, to: account, fileName: fileName, in: context)
            successMessage = "Imported \(batch.rowCount) transaction\(batch.rowCount == 1 ? "" : "s") into \(account.name)."
            previewRows = []
            classification = nil
            fileName = ""
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func existingFingerprints(for account: Account) -> Set<String> {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let id = account.id
        return Set(all.filter { $0.account?.id == id }.map(\.fingerprint))
    }
}

struct PreviewRow: Identifiable {
    let id = UUID()
    let row: NormalizedRow
    var isDuplicate: Bool
}

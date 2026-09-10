import Foundation
import SwiftData
import CryptoKit
import ImportKit

/// Turns CSV statements into pending `Transaction`s using an account's
/// import profile. Handles preview, stable fingerprints, and dedupe.
enum ImportService {

    struct PreviewResult {
        var rows: [NormalizedRow]
        var newCount: Int          // rows not already present for the account
        var duplicateCount: Int
    }

    /// Parse + normalize CSV without persisting anything.
    static func preview(csvText: String, profileYAML: String) throws -> [NormalizedRow] {
        let importer = try StatementImporter(yaml: profileYAML)
        return try importer.normalizedRows(fromCSV: csvText)
    }

    /// A stable content hash used to detect re-imports of the same line.
    static func fingerprint(accountID: UUID, row: NormalizedRow) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let canonical = [
            accountID.uuidString,
            iso.string(from: row.date),
            "\(row.amount)",
            "\(row.originalAmount)",
            row.originalCurrency,
            row.description,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute how many preview rows are new vs already imported for the account.
    @MainActor
    static func classify(rows: [NormalizedRow], account: Account, in context: ModelContext) -> PreviewResult {
        let existing = existingFingerprints(for: account, in: context)
        var dup = 0
        for row in rows where existing.contains(fingerprint(accountID: account.id, row: row)) { dup += 1 }
        return PreviewResult(rows: rows, newCount: rows.count - dup, duplicateCount: dup)
    }

    /// Persist preview rows as pending transactions under a new import batch,
    /// skipping rows already imported for the account. Returns the batch.
    @MainActor
    @discardableResult
    static func commit(rows: [NormalizedRow], to account: Account, fileName: String,
                       in context: ModelContext) throws -> ImportBatch {
        let existing = existingFingerprints(for: account, in: context)

        let batch = ImportBatch(fileName: fileName, rowCount: 0, account: account)
        context.insert(batch)

        var inserted = 0
        for row in rows {
            let fp = fingerprint(accountID: account.id, row: row)
            if existing.contains(fp) { continue }

            let tx = Transaction(
                date: row.date,
                descriptionText: row.description,
                rawDescription: row.description,
                amount: row.amount,
                originalAmount: row.originalAmount,
                originalCurrency: row.originalCurrency,
                status: .pending,
                sourceFile: fileName,
                fingerprint: fp
            )
            tx.account = account
            tx.importBatch = batch
            context.insert(tx)
            inserted += 1
        }
        batch.rowCount = inserted
        try context.save()
        return batch
    }

    @MainActor
    private static func existingFingerprints(for account: Account, in context: ModelContext) -> Set<String> {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let accountID = account.id
        return Set(all.filter { $0.account?.id == accountID }.map(\.fingerprint))
    }
}

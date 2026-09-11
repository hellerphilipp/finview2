import Foundation
import SQLite3

/// Exports accounts + transactions to portable formats.
///
/// The `.tallydb` export is a plain SQLite database using Tally's own schema:
/// two readable tables (`accounts`, `transactions`) keyed by the models' UUIDs,
/// with all Tally fields (category, work flag, transfer group, opening balance,
/// note). Openable by any SQLite tool, and re-importable without id collisions.
enum ExportService {

    // MARK: CSV

    static let csvColumns = ["Date", "Account", "Description", "Amount", "Currency",
                             "Original Amount", "Original Currency", "Category", "Work", "Status"]

    static func csv(for transactions: [Transaction]) -> String {
        var out = csvColumns.map(csvEscape).joined(separator: ",") + "\n"
        for tx in transactions {
            let fields = [
                isoDate.string(from: tx.date),
                tx.account?.name ?? "",
                tx.descriptionText,
                NSDecimalNumber(decimal: tx.amount).stringValue,
                tx.account?.currencyCode ?? "",
                NSDecimalNumber(decimal: tx.originalAmount).stringValue,
                tx.originalCurrency,
                tx.category?.displayPath ?? "",
                tx.isWorkExpense ? "yes" : "",
                tx.status.rawValue,
            ]
            out += fields.map(csvEscape).joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: SQLite

    struct ExportError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    @MainActor
    static func writeSQLite(to url: URL, accounts: [Account], transactions: [Transaction]) throws {
        try? FileManager.default.removeItem(at: url)   // overwrite (save panel already confirmed)

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw ExportError(message: "Could not create database at \(url.lastPathComponent).")
        }
        defer { sqlite3_close(db) }

        try exec(db, """
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              institution TEXT,
              currency TEXT NOT NULL,
              color_hex TEXT,
              is_expense_account INTEGER NOT NULL DEFAULT 0,
              import_profile TEXT
            );
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY,
              account_id TEXT NOT NULL,
              date TEXT NOT NULL,
              description TEXT NOT NULL,
              amount NUMERIC NOT NULL,
              original_amount NUMERIC NOT NULL,
              original_currency TEXT NOT NULL,
              status TEXT NOT NULL,
              category TEXT,
              is_work_expense INTEGER NOT NULL DEFAULT 0,
              is_opening_balance INTEGER NOT NULL DEFAULT 0,
              transfer_group_id TEXT,
              source_file TEXT,
              imported_at TEXT,
              note TEXT,
              FOREIGN KEY(account_id) REFERENCES accounts(id)
            );
            """)

        try exec(db, "BEGIN TRANSACTION;")

        let accountStmt = try prepare(db, "INSERT INTO accounts (id, name, institution, currency, color_hex, is_expense_account, import_profile) VALUES (?,?,?,?,?,?,?);")
        for account in accounts {
            sqlite3_reset(accountStmt)
            bindText(accountStmt, 1, account.id.uuidString)
            bindText(accountStmt, 2, account.name)
            bindText(accountStmt, 3, account.institution)
            bindText(accountStmt, 4, account.currencyCode)
            bindText(accountStmt, 5, account.colorHex)
            bindInt(accountStmt, 6, account.isExpenseAccount ? 1 : 0)
            bindText(accountStmt, 7, account.importProfile?.name)
            try step(db, accountStmt)
        }
        sqlite3_finalize(accountStmt)

        let txStmt = try prepare(db, """
            INSERT INTO transactions
            (id, account_id, date, description, amount, original_amount, original_currency,
             status, category, is_work_expense, is_opening_balance, transfer_group_id,
             source_file, imported_at, note)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """)
        for tx in transactions {
            guard let accountUUID = tx.account?.id.uuidString else { continue }
            sqlite3_reset(txStmt)
            bindText(txStmt, 1, tx.id.uuidString)
            bindText(txStmt, 2, accountUUID)
            bindText(txStmt, 3, dateTime.string(from: tx.date))
            bindText(txStmt, 4, tx.descriptionText)
            bindText(txStmt, 5, NSDecimalNumber(decimal: tx.amount).stringValue)
            bindText(txStmt, 6, NSDecimalNumber(decimal: tx.originalAmount).stringValue)
            bindText(txStmt, 7, tx.originalCurrency)
            bindText(txStmt, 8, tx.status.rawValue)
            bindText(txStmt, 9, tx.category?.displayPath)
            bindInt(txStmt, 10, tx.isWorkExpense ? 1 : 0)
            bindInt(txStmt, 11, tx.isOpeningBalance ? 1 : 0)
            bindText(txStmt, 12, tx.transferGroupID?.uuidString)
            bindText(txStmt, 13, tx.sourceFile)
            bindText(txStmt, 14, dateTime.string(from: tx.importedAt))
            bindText(txStmt, 15, tx.note)
            try step(db, txStmt)
        }
        sqlite3_finalize(txStmt)

        try exec(db, "COMMIT;")
    }

    // MARK: SQLite helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw ExportError(message: message)
        }
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ExportError(message: String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private static func step(_ db: OpaquePointer, _ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ExportError(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func bindInt(_ stmt: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(stmt, index, Int64(value))
    }

    // MARK: Formatters

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

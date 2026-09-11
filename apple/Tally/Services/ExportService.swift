import Foundation
import SQLite3

/// Exports accounts + transactions to portable formats.
///
/// The SQLite export mirrors the `statement-importer` Python schema
/// (`accounts` / `transactions` base columns) so the file round-trips with that
/// tool, and adds extra columns for Tally-specific data (category, work flag,
/// transfer group, opening balance, note) so nothing is lost.
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
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              currency TEXT NOT NULL,
              mapping_spec TEXT,
              institution TEXT,
              color_hex TEXT,
              is_expense_account INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY,
              account_id INTEGER NOT NULL,
              timestamp TEXT NOT NULL,
              description TEXT NOT NULL,
              amount NUMERIC NOT NULL,
              original_amount NUMERIC NOT NULL,
              original_currency TEXT NOT NULL,
              status TEXT NOT NULL,
              imported_at TEXT,
              source_file TEXT,
              category TEXT,
              is_work_expense INTEGER NOT NULL DEFAULT 0,
              is_opening_balance INTEGER NOT NULL DEFAULT 0,
              transfer_group_id TEXT,
              note TEXT,
              FOREIGN KEY(account_id) REFERENCES accounts(id)
            );
            """)

        try exec(db, "BEGIN TRANSACTION;")

        // Stable 1-based integer ids for FK compatibility.
        var accountID: [UUID: Int] = [:]
        let accountSQL = "INSERT INTO accounts (id, name, currency, mapping_spec, institution, color_hex, is_expense_account) VALUES (?,?,?,?,?,?,?);"
        let accountStmt = try prepare(db, accountSQL)
        for (index, account) in accounts.enumerated() {
            let rowID = index + 1
            accountID[account.id] = rowID
            sqlite3_reset(accountStmt)
            bindInt(accountStmt, 1, rowID)
            bindText(accountStmt, 2, account.name)
            bindText(accountStmt, 3, account.currencyCode)
            bindText(accountStmt, 4, account.importProfile?.name)
            bindText(accountStmt, 5, account.institution)
            bindText(accountStmt, 6, account.colorHex)
            bindInt(accountStmt, 7, account.isExpenseAccount ? 1 : 0)
            try step(db, accountStmt)
        }
        sqlite3_finalize(accountStmt)

        let txSQL = """
            INSERT INTO transactions
            (id, account_id, timestamp, description, amount, original_amount, original_currency,
             status, imported_at, source_file, category, is_work_expense, is_opening_balance,
             transfer_group_id, note)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
        let txStmt = try prepare(db, txSQL)
        for (index, tx) in transactions.enumerated() {
            guard let accID = tx.account.flatMap({ accountID[$0.id] }) else { continue }
            sqlite3_reset(txStmt)
            bindInt(txStmt, 1, index + 1)
            bindInt(txStmt, 2, accID)
            bindText(txStmt, 3, dateTime.string(from: tx.date))
            bindText(txStmt, 4, tx.descriptionText)
            bindText(txStmt, 5, NSDecimalNumber(decimal: tx.amount).stringValue)
            bindText(txStmt, 6, NSDecimalNumber(decimal: tx.originalAmount).stringValue)
            bindText(txStmt, 7, tx.originalCurrency)
            bindText(txStmt, 8, tx.status.rawValue)
            bindText(txStmt, 9, dateTime.string(from: tx.importedAt))
            bindText(txStmt, 10, tx.sourceFile)
            bindText(txStmt, 11, tx.category?.displayPath)
            bindInt(txStmt, 12, tx.isWorkExpense ? 1 : 0)
            bindInt(txStmt, 13, tx.isOpeningBalance ? 1 : 0)
            bindText(txStmt, 14, tx.transferGroupID?.uuidString)
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

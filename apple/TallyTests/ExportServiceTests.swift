import Testing
import Foundation
import SwiftData
import SQLite3

@MainActor
@Suite(.serialized)
struct ExportServiceTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    @Test func csvHasHeaderAndEscapesCommas() throws {
        let a = Account(name: "AMEX", institution: "X", currencyCode: "CHF")
        ctx.insert(a)
        let t = Transaction(descriptionText: "Coop, Zürich", amount: Decimal(string: "-42.5")!,
                            originalAmount: Decimal(string: "-42.5")!, originalCurrency: "CHF")
        t.account = a
        ctx.insert(t)

        let csv = ExportService.csv(for: [t])
        #expect(csv.hasPrefix("Date,Account,Description,Amount,Currency"))
        #expect(csv.contains("\"Coop, Zürich\""))     // comma-containing field is quoted
        #expect(csv.contains("-42.5"))
    }

    @Test func sqliteRoundTrips() throws {
        let current = Account(name: "Current", institution: "Bank", currencyCode: "CHF")
        let savings = Account(name: "Savings", institution: "Bank", currencyCode: "CHF")
        let groceries = SpendingCategory(name: "Groceries")
        [current, savings].forEach { ctx.insert($0) }
        ctx.insert(groceries)

        let t1 = Transaction(descriptionText: "COOP", amount: Decimal(string: "-42.5")!,
                             originalAmount: Decimal(string: "-42.5")!, originalCurrency: "CHF")
        t1.account = current; t1.category = groceries; t1.isWorkExpense = true
        let t2 = Transaction(descriptionText: "Salary", amount: Decimal(string: "1000")!,
                             originalAmount: Decimal(string: "1000")!, originalCurrency: "CHF")
        t2.account = savings
        ctx.insert(t1); ctx.insert(t2)
        try ctx.save()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tally-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.writeSQLite(to: url,
                                      accounts: try ctx.fetch(FetchDescriptor<Account>()),
                                      transactions: try ctx.fetch(FetchDescriptor<Transaction>()))

        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        #expect(scalarInt(db, "SELECT COUNT(*) FROM accounts") == 2)
        #expect(scalarInt(db, "SELECT COUNT(*) FROM transactions") == 2)
        // The FK resolves to a real account.
        #expect(scalarInt(db, "SELECT COUNT(*) FROM transactions t JOIN accounts a ON a.id = t.account_id") == 2)
        // Tally-specific columns preserved.
        #expect(scalarString(db, "SELECT description FROM transactions WHERE is_work_expense = 1") == "COOP")
        #expect(scalarString(db, "SELECT category FROM transactions WHERE is_work_expense = 1") == "Groceries")
    }

    // MARK: sqlite read helpers

    private func scalarInt(_ db: OpaquePointer?, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func scalarString(_ db: OpaquePointer?, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }
}

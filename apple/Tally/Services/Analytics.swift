import Foundation

/// Pure aggregation helpers for the dashboard and reports. Operate on model
/// objects but contain no persistence, so they're easy to unit-test.
enum Analytics {

    /// Transactions counted toward balances/spend (everything not rejected).
    static func active(_ txs: [Transaction]) -> [Transaction] {
        txs.filter { $0.status != .rejected }
    }

    /// Account balance = sum of active transaction amounts (spend is negative).
    static func balance(of account: Account) -> Decimal {
        active(account.txs).reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Most recent activity for an account (latest transaction or import time).
    static func lastActivity(of account: Account) -> Date? {
        let txs = account.txs
        let latestTx = txs.map(\.date).max()
        let latestImport = txs.map(\.importedAt).max()
        return [latestTx, latestImport].compactMap { $0 }.max()
    }

    /// True when the newest data is older than `days` (needs a fresh import).
    static func isStale(_ account: Account, asOf now: Date = .now, days: Int = 35) -> Bool {
        guard let last = lastActivity(of: account) else { return true }
        return now.timeIntervalSince(last) > Double(days) * 86_400
    }

    /// Total spending (positive number) since a date across the given txs.
    static func spending(_ txs: [Transaction], since: Date) -> Decimal {
        active(txs)
            .filter { $0.date >= since && $0.amount < 0 }
            .reduce(Decimal.zero) { $0 - $1.amount }
    }

    /// Spending grouped by top-level category name (positive amounts).
    static func spendingByCategory(_ txs: [Transaction], since: Date? = nil) -> [(name: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for tx in active(txs) where tx.amount < 0 {
            if let since, tx.date < since { continue }
            let name = topLevelName(tx.category)
            totals[name, default: .zero] += -tx.amount
        }
        return totals.map { (name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Spending per (month, category) for stacked/bar charts.
    struct MonthlyCategorySpend: Identifiable {
        var id: String { "\(month.timeIntervalSince1970)-\(category)" }
        let month: Date
        let category: String
        let amount: Decimal
    }

    static func monthlyCategorySpending(_ txs: [Transaction],
                                        calendar: Calendar = .current) -> [MonthlyCategorySpend] {
        var totals: [Date: [String: Decimal]] = [:]
        for tx in active(txs) where tx.amount < 0 {
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            guard let month = calendar.date(from: comps) else { continue }
            totals[month, default: [:]][topLevelName(tx.category), default: .zero] += -tx.amount
        }
        return totals.flatMap { month, cats in
            cats.map { MonthlyCategorySpend(month: month, category: $0.key, amount: $0.value) }
        }
        .sorted { $0.month < $1.month }
    }

    private static func topLevelName(_ category: SpendingCategory?) -> String {
        guard let category else { return "Uncategorized" }
        return category.parent?.name ?? category.name
    }
}

import Foundation

/// Pure aggregation helpers for the dashboard and reports. Operate on model
/// objects but contain no persistence, so they're easy to unit-test.
enum Analytics {

    /// A transaction explicitly filed under a transfer-kind category, which is an
    /// escape hatch to keep a *lone, unlinked* transfer out of spending. Linked
    /// groups (transfers or refunds) are handled by netting in the aggregations
    /// below, not by exclusion here.
    static func isTransfer(_ tx: Transaction) -> Bool {
        tx.category?.kind == .transfer
    }

    /// Transactions that count as real spending/income (non-transfer, excluding
    /// synthetic opening-balance entries).
    static func spendable(_ txs: [Transaction]) -> [Transaction] {
        txs.filter { !isTransfer($0) && !$0.isOpeningBalance }
    }

    /// Default report bucket for a transaction: its top-level category name.
    static func defaultCategoryName(_ tx: Transaction) -> String {
        topLevelName(tx.category)
    }

    /// Account balance = sum of transaction amounts (spend is negative).
    static func balance(of account: Account) -> Decimal {
        account.txs.reduce(Decimal.zero) { $0 + $1.amount }
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
    ///
    /// A transaction counts when it's a plain charge (negative) or a member of a
    /// link group; each contributes its signed amount, so a group nets (a refund
    /// subtracts from its charge, a transfer's legs cancel). Lone positive
    /// amounts (income, an unlinked stray refund) are ignored.
    static func spending(_ txs: [Transaction], since: Date) -> Decimal {
        spendable(txs)
            .filter { $0.date >= since && ($0.amount < 0 || $0.isLinked) }
            .reduce(Decimal.zero) { $0 - $1.amount }
    }

    /// Spending grouped by bucket name (positive amounts). `classify` returns a
    /// bucket name, or nil to exclude a transaction (e.g. filtering work items).
    static func spendingByCategory(_ txs: [Transaction], since: Date? = nil,
                                   classify: (Transaction) -> String? = defaultCategoryName) -> [(name: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for tx in spendable(txs) where tx.amount < 0 || tx.isLinked {
            if let since, tx.date < since { continue }
            guard let name = classify(tx) else { continue }
            totals[name, default: .zero] += -tx.amount
        }
        return totals.map { (name: $0.key, amount: $0.value) }
            .filter { $0.amount > 0 }   // drop buckets that net to zero (full refunds)
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
                                        calendar: Calendar = .current,
                                        classify: (Transaction) -> String? = defaultCategoryName) -> [MonthlyCategorySpend] {
        var totals: [Date: [String: Decimal]] = [:]
        for tx in spendable(txs) where tx.amount < 0 || tx.isLinked {
            guard let name = classify(tx) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            guard let month = calendar.date(from: comps) else { continue }
            totals[month, default: [:]][name, default: .zero] += -tx.amount
        }
        return totals.flatMap { month, cats in
            cats.map { MonthlyCategorySpend(month: month, category: $0.key, amount: $0.value) }
        }
        .filter { $0.amount > 0 }   // drop month/category buckets that net to zero
        .sorted { $0.month < $1.month }
    }

    private static func topLevelName(_ category: SpendingCategory?) -> String {
        guard let category else { return "Uncategorized" }
        return category.parent?.name ?? category.name
    }

    // MARK: - Foreign currency

    /// Per-currency roll-up of foreign spending: how much was spent in the
    /// original currency vs how much was deducted in the account currency.
    struct CurrencySummary: Identifiable {
        var id: String { currency }
        let currency: String            // the foreign (original) currency
        let accountCurrency: String     // what it was deducted in
        let spentOriginal: Decimal      // positive, in `currency`
        let deductedAccount: Decimal    // positive, in `accountCurrency`
        let count: Int
        /// Effective rate: account units paid per 1 unit of foreign currency.
        var impliedRate: Decimal { spentOriginal == 0 ? 0 : deductedAccount / spentOriginal }
    }

    static func foreignTransactions(_ txs: [Transaction]) -> [Transaction] {
        spendable(txs).filter { $0.isForeignCurrency && $0.amount < 0 }
    }

    static func foreignSummaries(_ txs: [Transaction]) -> [CurrencySummary] {
        var spent: [String: Decimal] = [:]
        var deducted: [String: Decimal] = [:]
        var accountCurrency: [String: String] = [:]
        var counts: [String: Int] = [:]
        for tx in foreignTransactions(txs) {
            let ccy = tx.originalCurrency
            spent[ccy, default: .zero] += -tx.originalAmount
            deducted[ccy, default: .zero] += -tx.amount
            accountCurrency[ccy] = tx.account?.currencyCode ?? ""
            counts[ccy, default: 0] += 1
        }
        return spent.keys.map { ccy in
            CurrencySummary(currency: ccy,
                            accountCurrency: accountCurrency[ccy] ?? "",
                            spentOriginal: spent[ccy] ?? .zero,
                            deductedAccount: deducted[ccy] ?? .zero,
                            count: counts[ccy] ?? 0)
        }
        .sorted { $0.deductedAccount > $1.deductedAccount }
    }
}

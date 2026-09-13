import Foundation
import SwiftData

/// Reconciles work-tagged card charges against line items in the designated
/// work expense account. A card charge of −X should be mirrored by a +X line
/// item posted in the expense account; charges with no matching line item are
/// "missing" — you probably forgot to expense them. Purely informational.
enum ExpenseReconciler {

    struct Result {
        var expenseAccount: Account?
        var missing: [Transaction]      // work charges not yet posted as expenses
        var matched: [(charge: Transaction, lineItem: Transaction)]
        var missingTotal: Decimal       // sum of |missing amounts|
        var matchedCount: Int { matched.count }
    }

    static func expenseAccount(in accounts: [Account]) -> Account? {
        accounts.first { $0.isExpenseAccount }
    }

    /// Match each work-tagged charge (−X, not on the expense account) to a
    /// +X line item on the expense account. Greedy nearest-date, 1:1.
    static func reconcile(transactions: [Transaction], accounts: [Account],
                          maxDaysAfter: Int = 180, maxDaysBefore: Int = 5,
                          calendar: Calendar = .current) -> Result {
        guard let expense = expenseAccount(in: accounts) else {
            return Result(expenseAccount: nil, missing: [], matched: [], missingTotal: .zero)
        }

        let charges = transactions
            .filter { $0.isWorkExpense && !$0.isOpeningBalance
                      && $0.amount < 0 && $0.account?.id != expense.id }
            .sorted { $0.date < $1.date }
        var lineItems = transactions
            .filter { $0.account?.id == expense.id && $0.amount > 0
                      && !$0.isOpeningBalance }

        var missing: [Transaction] = []
        var matched: [(charge: Transaction, lineItem: Transaction)] = []

        for charge in charges {
            let target = -charge.amount
            let candidates = lineItems.enumerated().filter { _, item in
                guard item.amount == target else { return false }
                let gap = calendar.dateComponents([.day], from: charge.date, to: item.date).day ?? Int.min
                return gap >= -maxDaysBefore && gap <= maxDaysAfter
            }
            if let (index, item) = candidates.min(by: { lhs, rhs in
                abs(lhs.element.date.timeIntervalSince(charge.date)) < abs(rhs.element.date.timeIntervalSince(charge.date))
            }) {
                matched.append((charge: charge, lineItem: item))
                lineItems.remove(at: index)
            } else {
                missing.append(charge)
            }
        }

        let total = missing.reduce(Decimal.zero) { $0 - $1.amount }
        return Result(expenseAccount: expense,
                      missing: missing.sorted { $0.date > $1.date },
                      matched: matched,
                      missingTotal: total)
    }

    /// Propagate the category from each matched card charge onto its expense-
    /// account line item (only when the line item is uncategorized). Returns the
    /// number of line items updated.
    @MainActor
    @discardableResult
    static func inheritCategories(from result: Result, in context: ModelContext) -> Int {
        var count = 0
        for pair in result.matched where pair.lineItem.category == nil {
            if let category = pair.charge.category {
                pair.lineItem.category = category
                count += 1
            }
        }
        if count > 0 { try? context.save() }
        return count
    }
}

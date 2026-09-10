import Foundation

/// Reconciles work-tagged card charges against line items in the designated
/// work expense account. A card charge of −X should be mirrored by a +X line
/// item posted in the expense account; charges with no matching line item are
/// "missing" — you probably forgot to expense them. Purely informational.
enum ExpenseReconciler {

    struct Result {
        var expenseAccount: Account?
        var missing: [Transaction]      // work charges not yet posted as expenses
        var matchedCount: Int
        var missingTotal: Decimal       // sum of |missing amounts|
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
            return Result(expenseAccount: nil, missing: [], matchedCount: 0, missingTotal: .zero)
        }

        let charges = transactions
            .filter { $0.isWorkExpense && $0.status != .rejected && $0.amount < 0 && $0.account?.id != expense.id }
            .sorted { $0.date < $1.date }
        var lineItems = transactions
            .filter { $0.account?.id == expense.id && $0.amount > 0 && $0.status != .rejected }

        var missing: [Transaction] = []
        var matched = 0

        for charge in charges {
            let target = -charge.amount
            // Candidate line items: equal magnitude, within the date window,
            // not yet consumed. Prefer the nearest date.
            let candidates = lineItems.enumerated().filter { _, item in
                guard item.amount == target else { return false }
                let gap = calendar.dateComponents([.day], from: charge.date, to: item.date).day ?? Int.min
                return gap >= -maxDaysBefore && gap <= maxDaysAfter
            }
            if let (index, _) = candidates.min(by: { lhs, rhs in
                abs(lhs.element.date.timeIntervalSince(charge.date)) < abs(rhs.element.date.timeIntervalSince(charge.date))
            }) {
                lineItems.remove(at: index)
                matched += 1
            } else {
                missing.append(charge)
            }
        }

        let total = missing.reduce(Decimal.zero) { $0 - $1.amount }
        return Result(expenseAccount: expense,
                      missing: missing.sorted { $0.date > $1.date },
                      matchedCount: matched,
                      missingTotal: total)
    }
}

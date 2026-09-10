import SwiftUI
import SwiftData

struct WorkExpensesView: View {
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]

    private var result: ExpenseReconciler.Result {
        ExpenseReconciler.reconcile(transactions: transactions, accounts: accounts)
    }

    var body: some View {
        Group {
            if result.expenseAccount == nil {
                ContentUnavailableView {
                    Label("No Expense Account", systemImage: "briefcase")
                } description: {
                    Text("Mark one account as your work expense account (edit it in Accounts) to see which work-tagged charges you haven't expensed yet.")
                }
            } else {
                content(expenseName: result.expenseAccount?.name ?? "")
            }
        }
        .navigationTitle("Work Expenses")
    }

    @ViewBuilder
    private func content(expenseName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar(expenseName: expenseName)
            Divider()
            if result.missing.isEmpty {
                ContentUnavailableView("All Expensed", systemImage: "checkmark.seal",
                                       description: Text("Every work-tagged charge has a matching line item in \(expenseName)."))
            } else {
                Table(result.missing) {
                    TableColumn("Date") { Text(DateText.string($0.date)) }.width(min: 90, ideal: 100)
                    TableColumn("Account") { Text($0.account?.name ?? "—") }
                    TableColumn("Description") { Text($0.descriptionText).lineLimit(1) }
                    TableColumn("Amount") { tx in
                        Text(Money.string(tx.amount, currency: tx.account?.currencyCode ?? ""))
                            .monospacedDigit().foregroundStyle(.orange)
                    }
                    .width(min: 90, ideal: 110)
                }
            }
        }
    }

    private func summaryBar(expenseName: String) -> some View {
        HStack(spacing: 16) {
            Label {
                Text("\(result.missing.count) not yet in \(expenseName)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.headline)

            if result.missingTotal > 0 {
                Text("· \(Money.string(result.missingTotal, currency: result.expenseAccount?.currencyCode ?? "CHF")) unclaimed")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(result.matchedCount) matched", systemImage: "checkmark.circle")
                .foregroundStyle(.green).font(.callout)
        }
        .padding(12)
    }
}

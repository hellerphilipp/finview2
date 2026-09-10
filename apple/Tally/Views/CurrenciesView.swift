import SwiftUI
import SwiftData

struct CurrenciesView: View {
    @Query private var transactions: [Transaction]

    private var summaries: [Analytics.CurrencySummary] { Analytics.foreignSummaries(transactions) }
    private var foreignTxs: [Transaction] {
        Analytics.foreignTransactions(transactions).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if summaries.isEmpty {
                ContentUnavailableView("No Foreign Spending", systemImage: "globe",
                                       description: Text("Transactions charged in a currency other than the account's currency will appear here, showing what you spent vs. what was deducted."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryCards
                        detailTable
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Currencies")
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(summaries) { s in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(s.currency, systemImage: "globe").font(.headline)
                        Spacer()
                        Text("\(s.count) tx").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Spent").font(.caption).foregroundStyle(.secondary)
                        Text(Money.string(s.spentOriginal, currency: s.currency)).bold().monospacedDigit()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Deducted").font(.caption).foregroundStyle(.secondary)
                        Text(Money.string(s.deductedAccount, currency: s.accountCurrency))
                            .bold().monospacedDigit().foregroundStyle(.orange)
                    }
                    Divider()
                    Text("≈ \(rate(s)) \(s.accountCurrency)/\(s.currency)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var detailTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Foreign Transactions").font(.title3.bold())
            Table(foreignTxs) {
                TableColumn("Date") { Text(DateText.string($0.date)) }.width(min: 90, ideal: 100)
                TableColumn("Description") { Text($0.descriptionText).lineLimit(1) }
                TableColumn("Spent") { tx in
                    Text(Money.string(-tx.originalAmount, currency: tx.originalCurrency)).monospacedDigit()
                }
                TableColumn("Deducted") { tx in
                    Text(Money.string(-tx.amount, currency: tx.account?.currencyCode ?? ""))
                        .monospacedDigit().foregroundStyle(.orange)
                }
                TableColumn("Rate") { tx in
                    Text(txRate(tx)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                .width(70)
            }
            .frame(minHeight: 240)
        }
    }

    private func rate(_ s: Analytics.CurrencySummary) -> String {
        String(format: "%.4f", (s.impliedRate as NSDecimalNumber).doubleValue)
    }
    private func txRate(_ tx: Transaction) -> String {
        let orig = abs((tx.originalAmount as NSDecimalNumber).doubleValue)
        guard orig > 0 else { return "—" }
        return String(format: "%.3f", abs((tx.amount as NSDecimalNumber).doubleValue) / orig)
    }
}

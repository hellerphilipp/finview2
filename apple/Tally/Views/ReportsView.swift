import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query private var transactions: [Transaction]

    private var monthly: [Analytics.MonthlyCategorySpend] {
        Analytics.monthlyCategorySpending(transactions)
    }
    private var months: [Date] {
        Array(Set(monthly.map(\.month))).sorted()
    }
    private var categories: [String] {
        Array(Set(monthly.map(\.category))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if monthly.isEmpty {
                    ContentUnavailableView("No Data Yet", systemImage: "chart.bar",
                                           description: Text("Import and categorize transactions to see reports."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    chartSection
                    pivotSection
                }
            }
            .padding(20)
        }
        .navigationTitle("Reports")
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending by Category, per Month").font(.title3.bold())
            Chart(monthly) { entry in
                BarMark(
                    x: .value("Month", entry.month, unit: .month),
                    y: .value("Spend", (entry.amount as NSDecimalNumber).doubleValue)
                )
                .foregroundStyle(by: .value("Category", entry.category))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 280)
        }
    }

    private var pivotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pivot").font(.title3.bold())
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Category").bold()
                        ForEach(months, id: \.self) { m in
                            Text(m, format: .dateTime.month(.abbreviated).year()).bold()
                        }
                        Text("Total").bold()
                    }
                    Divider()
                    ForEach(categories, id: \.self) { cat in
                        GridRow {
                            Text(cat)
                            ForEach(months, id: \.self) { m in
                                Text(cell(cat, m)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Text(rowTotal(cat)).monospacedDigit().bold()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func amount(_ category: String, _ month: Date) -> Decimal {
        monthly.first { $0.category == category && $0.month == month }?.amount ?? .zero
    }
    private func cell(_ category: String, _ month: Date) -> String {
        let a = amount(category, month)
        return a == .zero ? "—" : Money.string(a, currency: currency)
    }
    private func rowTotal(_ category: String) -> String {
        let total = months.reduce(Decimal.zero) { $0 + amount(category, $1) }
        return Money.string(total, currency: currency)
    }
    private var currency: String { transactions.first?.account?.currencyCode ?? "CHF" }
}

import SwiftUI
import SwiftData

struct RecurringView: View {
    @Query private var transactions: [Transaction]

    private var series: [RecurrenceDetector.Series] {
        RecurrenceDetector.detect(transactions)
    }

    var body: some View {
        Group {
            if series.isEmpty {
                ContentUnavailableView("No Recurring Transactions", systemImage: "repeat",
                                       description: Text("Once a merchant appears on a regular monthly, quarterly, or yearly cadence, it shows up here."))
            } else {
                Table(series) {
                    TableColumn("Merchant") { Text($0.merchant).bold() }
                    TableColumn("Cadence") { s in
                        Text(s.cadence.label)
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    .width(90)
                    TableColumn("Amount") { s in
                        Text(Money.string(s.averageAmount, currency: s.currency)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("Seen") { Text("\($0.occurrences)×") }
                        .width(50)
                    TableColumn("Last") { Text(DateText.string($0.lastDate)) }
                    TableColumn("Next expected") { Text(DateText.string($0.nextExpected)).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Recurring")
    }
}

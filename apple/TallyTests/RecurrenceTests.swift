import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct RecurrenceTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func account() -> Account {
        let a = Account(name: "Card", institution: "Bank", currencyCode: "CHF")
        ctx.insert(a); return a
    }

    private func tx(_ acc: Account, _ desc: String, _ amount: String, _ date: Date) {
        let t = Transaction(date: date, descriptionText: desc, amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: "CHF")
        t.account = acc
        ctx.insert(t)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    @Test func detectsMonthlySubscription() throws {
        let a = account()
        // Netflix ~monthly for 4 months.
        for m in 1...4 { tx(a, "Netflix.com (Netflix)", "-19.90", date(2025, m, 15)) }
        // A one-off that should not be flagged.
        tx(a, "Random (OneOff)", "-5.00", date(2025, 2, 2))
        try ctx.save()

        let series = RecurrenceDetector.detect(a.txs)
        #expect(series.count == 1)
        let s = try #require(series.first)
        #expect(s.merchant == "Netflix")
        #expect(s.cadence == .monthly)
        #expect(s.occurrences == 4)
        #expect(s.averageAmount == Decimal(string: "-19.9"))
    }

    @Test func ignoresInconsistentAmounts() throws {
        let a = account()
        // Same merchant monthly but wildly varying amounts → not "recurring".
        tx(a, "Shop (Groceries)", "-10.00", date(2025, 1, 10))
        tx(a, "Shop (Groceries)", "-90.00", date(2025, 2, 10))
        tx(a, "Shop (Groceries)", "-5.00", date(2025, 3, 10))
        try ctx.save()
        #expect(RecurrenceDetector.detect(a.txs).isEmpty)
    }

    @Test func cadenceClassification() {
        #expect(RecurrenceDetector.cadence(forMedianGap: 30) == .monthly)
        #expect(RecurrenceDetector.cadence(forMedianGap: 91) == .quarterly)
        #expect(RecurrenceDetector.cadence(forMedianGap: 365) == .yearly)
        #expect(RecurrenceDetector.cadence(forMedianGap: 7) == nil)
    }
}

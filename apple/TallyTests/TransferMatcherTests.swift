import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct TransferMatcherTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func account(_ name: String, _ currency: String = "CHF") -> Account {
        let a = Account(name: name, institution: "Bank", currencyCode: currency)
        ctx.insert(a); return a
    }

    @discardableResult
    private func tx(_ acc: Account, _ amount: String, _ date: Date) -> Transaction {
        let t = Transaction(date: date, descriptionText: "transfer", amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: acc.currencyCode)
        t.account = acc; ctx.insert(t); return t
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    @Test func matchesEqualOppositeAcrossAccounts() throws {
        let current = account("Current"), savings = account("Savings")
        tx(current, "-2000.00", date(2025, 1, 10))
        tx(savings, "2000.00", date(2025, 1, 11))
        tx(current, "-42.50", date(2025, 1, 12))          // unrelated spend
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let candidates = TransferMatcher.candidates(all)
        #expect(candidates.count == 1)
        let c = try #require(candidates.first)
        #expect(c.amount == Decimal(string: "2000"))
        #expect(c.dayGap == 1)
        #expect(c.outgoing.account?.name == "Current")
        #expect(c.incoming.account?.name == "Savings")
    }

    @Test func doesNotMatchSameAccountOrDifferentCurrency() throws {
        let current = account("Current"), eur = account("EUR Acct", "EUR")
        tx(current, "-100.00", date(2025, 1, 10))
        tx(current, "100.00", date(2025, 1, 10))          // same account
        tx(eur, "100.00", date(2025, 1, 10))              // different currency
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).isEmpty)
    }

    @Test func confirmLinksBothAndExcludesFromSpending() throws {
        let current = account("Current"), savings = account("Savings")
        let out = tx(current, "-2000.00", date(2025, 1, 10))
        tx(savings, "2000.00", date(2025, 1, 11))
        try ctx.save()

        var all = try ctx.fetch(FetchDescriptor<Transaction>())
        let candidate = try #require(TransferMatcher.candidates(all).first)
        TransferMatcher.confirm(candidate, in: ctx)

        all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.allSatisfy { $0.transferGroupID != nil })
        #expect(out.status == .confirmed)
        // The −2000 outgoing must not count as spending anymore.
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == .zero)
        // No further candidates once grouped.
        #expect(TransferMatcher.candidates(all).isEmpty)
    }

    @Test func unlinkClearsGroup() throws {
        let current = account("Current"), savings = account("Savings")
        tx(current, "-500.00", date(2025, 2, 1))
        tx(savings, "500.00", date(2025, 2, 1))
        try ctx.save()
        var all = try ctx.fetch(FetchDescriptor<Transaction>())
        let candidate = try #require(TransferMatcher.candidates(all).first)
        TransferMatcher.confirm(candidate, in: ctx)

        all = try ctx.fetch(FetchDescriptor<Transaction>())
        let gid = try #require(all.first?.transferGroupID)
        TransferMatcher.unlink(groupID: gid, in: all, context: ctx)

        all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.allSatisfy { $0.transferGroupID == nil })
        #expect(TransferMatcher.candidates(all).count == 1)     // matchable again
    }
}

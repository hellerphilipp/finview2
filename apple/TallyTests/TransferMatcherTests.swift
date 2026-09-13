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

    @Test func canLinkAcceptsValidPairAndLinks() throws {
        let current = account("Current"), savings = account("Savings")
        let out = tx(current, "-750.00", date(2025, 3, 1))
        let inc = tx(savings, "750.00", date(2025, 3, 25))  // 24d apart — beyond auto-match gap, still hand-linkable
        try ctx.save()

        // Confirms the day gap never gates manual linking.
        #expect(TransferMatcher.candidates([out, inc]).isEmpty)

        #expect(TransferMatcher.canLink([out, inc]))
        TransferMatcher.link([out, inc], in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.allSatisfy { $0.transferGroupID != nil })
        #expect(out.status == .confirmed && inc.status == .confirmed)
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == .zero)
    }

    @Test func canLinkRejectsInvalidSelections() throws {
        let current = account("Current"), savings = account("Savings"), eur = account("EUR Acct", "EUR")
        let out = tx(current, "-100.00", date(2025, 1, 10))
        let inc = tx(savings, "100.00", date(2025, 1, 10))
        let sameAcct = tx(current, "100.00", date(2025, 1, 10))
        let eurLeg = tx(eur, "100.00", date(2025, 1, 10))
        let unequal = tx(savings, "90.00", date(2025, 1, 10))
        try ctx.save()

        #expect(!TransferMatcher.canLink([out]))                 // only one row
        #expect(!TransferMatcher.canLink([out, inc, sameAcct]))  // three rows
        #expect(!TransferMatcher.canLink([out, sameAcct]))       // same account
        #expect(!TransferMatcher.canLink([out, eurLeg]))         // different currency
        #expect(!TransferMatcher.canLink([out, unequal]))        // not equal-and-opposite

        // Already-linked rows can't be re-linked.
        TransferMatcher.link([out, inc], in: ctx)
        let out2 = tx(current, "-100.00", date(2025, 1, 11))
        try ctx.save()
        #expect(!TransferMatcher.canLink([out, out2]))
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
        // Linking confirmed the legs, so they're no longer *pending* — the
        // suggester leaves reviewed transactions alone until re-opened.
        #expect(TransferMatcher.candidates(all).isEmpty)
        all.forEach { $0.status = .pending }
        #expect(TransferMatcher.candidates(all).count == 1)     // matchable again once pending
    }

    @Test func suggestsOnlyPendingLegs() throws {
        let current = account("Current"), savings = account("Savings")
        let out = tx(current, "-300.00", date(2025, 4, 1))
        tx(savings, "300.00", date(2025, 4, 2))
        try ctx.save()
        var all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).count == 1)

        out.status = .confirmed                                  // one leg already reviewed
        try ctx.save()
        all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).isEmpty)
    }

    @Test func onlySuggestsUncategorizedOrTransferCategory() throws {
        let current = account("Current"), savings = account("Savings")
        let spending = SpendingCategory(name: "Groceries", kind: .spending)
        let transfer = SpendingCategory(name: "Transfers", kind: .transfer)
        ctx.insert(spending); ctx.insert(transfer)
        let out = tx(current, "-400.00", date(2025, 5, 1))
        tx(savings, "400.00", date(2025, 5, 2))
        try ctx.save()

        // A non-transfer category on a leg disqualifies the pair.
        out.category = spending
        try ctx.save()
        var all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).isEmpty)

        // Filed under a transfer-kind category, it's eligible again.
        out.category = transfer
        try ctx.save()
        all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).count == 1)
    }

    @Test func respectsTenDayDefaultGap() throws {
        let current = account("Current"), savings = account("Savings")
        tx(current, "-600.00", date(2025, 6, 1))
        let inc = tx(savings, "600.00", date(2025, 6, 10))      // 9 days apart
        try ctx.save()
        var all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).count == 1)

        inc.date = date(2025, 6, 12)                            // 11 days apart
        try ctx.save()
        all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(TransferMatcher.candidates(all).isEmpty)
    }
}

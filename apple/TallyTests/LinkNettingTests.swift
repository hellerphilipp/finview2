import Testing
import Foundation
import SwiftData

/// Uniform group-net spending math: a linked group contributes the *net* of its
/// signed amounts to its shared category. Transfers net to zero; partial refunds
/// net to the remainder.
@MainActor
@Suite(.serialized)
struct LinkNettingTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func account(_ name: String, _ currency: String = "CHF") -> Account {
        let a = Account(name: name, institution: "Bank", currencyCode: currency)
        ctx.insert(a); return a
    }

    @discardableResult
    private func tx(_ acc: Account, _ amount: String, _ d: Date,
                    category: SpendingCategory? = nil) -> Transaction {
        let t = Transaction(date: d, descriptionText: "x", amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: acc.currencyCode)
        t.account = acc; t.category = category; ctx.insert(t); return t
    }

    private func shopping() -> SpendingCategory {
        let c = SpendingCategory(name: "Shopping", kind: .spending); ctx.insert(c); return c
    }

    @Test func partialRefundNetsAgainstCategory() throws {
        let card = account("Card")
        let shop = shopping()
        let charge = tx(card, "-250.00", date(2025, 3, 1), category: shop)
        let refund = tx(card, "50.00", date(2025, 3, 10), category: shop)
        LinkService.link([charge, refund], kind: .refund, in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        // Total spend since Jan is the net 200, not the gross 250.
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == Decimal(string: "200"))
        let shoppingTotal = Analytics.spendingByCategory(all).first { $0.name == "Shopping" }?.amount
        #expect(shoppingTotal == Decimal(string: "200"))
    }

    @Test func fullRefundNetsToZero() throws {
        let card = account("Card")
        let shop = shopping()
        let charge = tx(card, "-10.00", date(2025, 3, 1), category: shop)
        let refund = tx(card, "10.00", date(2025, 3, 5), category: shop)
        LinkService.link([charge, refund], kind: .refund, in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == .zero)
        #expect(Analytics.spendingByCategory(all).first { $0.name == "Shopping" } == nil
                || Analytics.spendingByCategory(all).first { $0.name == "Shopping" }?.amount == .zero)
    }

    @Test func crossAccountReimbursementNetsInCategory() throws {
        // Group dinner on card, friend Venmos half to current — a cross-account refund.
        let card = account("Card"), current = account("Current")
        let dining = SpendingCategory(name: "Dining", kind: .spending); ctx.insert(dining)
        let charge = tx(card, "-100.00", date(2025, 4, 1), category: dining)
        let back = tx(current, "50.00", date(2025, 4, 3), category: dining)
        LinkService.link([charge, back], kind: .refund, in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == Decimal(string: "50"))
    }

    @Test func loneRefundStillIgnoredUntilLinked() throws {
        // An unlinked positive amount is not spending and does not reduce a category.
        let card = account("Card")
        let shop = shopping()
        tx(card, "-250.00", date(2025, 3, 1), category: shop)
        tx(card, "50.00", date(2025, 3, 10), category: shop)   // not linked

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(Analytics.spending(all, since: date(2025, 1, 1)) == Decimal(string: "250"))
    }
}

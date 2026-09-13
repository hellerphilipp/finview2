import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct TransactionSearchTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// A Netflix charge of -64.00 CHF, categorized, tagged, on a CHF card.
    private func sampleTransaction() -> Transaction {
        let acc = Account(name: "Everyday Card", institution: "Bank", currencyCode: "CHF")
        ctx.insert(acc)
        let parent = SpendingCategory(name: "Subscriptions")
        let cat = SpendingCategory(name: "Streaming", parent: parent)
        ctx.insert(parent); ctx.insert(cat)
        let merchant = Merchant(canonicalName: "Netflix")
        ctx.insert(merchant)
        let tag = Tag(name: "recurring")
        ctx.insert(tag)

        let t = Transaction(date: day(2025, 3, 12), descriptionText: "NETFLIX.COM",
                            rawDescription: "NETFLIX.COM 866-579-7172", amount: Decimal(string: "-64.00")!,
                            originalAmount: Decimal(string: "-64.00")!, originalCurrency: "CHF")
        t.account = acc
        t.category = cat
        t.merchant = merchant
        t.tags = [tag]
        t.note = "family plan"
        ctx.insert(t)
        return t
    }

    @Test func blankQueryMatchesEverything() {
        let t = sampleTransaction()
        #expect(t.matches(searchTerms: searchTerms("")))
        #expect(t.matches(searchTerms: searchTerms("   ")))
    }

    @Test func matchesDescriptionCaseInsensitively() {
        let t = sampleTransaction()
        #expect(t.matches(searchTerms: searchTerms("netflix")))
        #expect(t.matches(searchTerms: searchTerms("NETFLIX")))
    }

    @Test func matchesMerchantCategoryTagAndNote() {
        let t = sampleTransaction()
        #expect(t.matches(searchTerms: searchTerms("streaming")))   // category path
        #expect(t.matches(searchTerms: searchTerms("subscriptions"))) // parent in path
        #expect(t.matches(searchTerms: searchTerms("recurring")))    // tag
        #expect(t.matches(searchTerms: searchTerms("family")))       // note
        #expect(t.matches(searchTerms: searchTerms("everyday")))     // account name
    }

    @Test func matchesAmountAndCurrency() {
        let t = sampleTransaction()
        #expect(t.matches(searchTerms: searchTerms("64")))
        #expect(t.matches(searchTerms: searchTerms("CHF")))
        // "CHF 64" — two terms, both present (currency + amount) though not adjacent.
        #expect(t.matches(searchTerms: searchTerms("CHF 64")))
    }

    @Test func allTermsMustMatch() {
        let t = sampleTransaction()
        #expect(t.matches(searchTerms: searchTerms("netflix streaming")))
        #expect(!t.matches(searchTerms: searchTerms("netflix spotify")))
    }

    @Test func nonMatchingQueryFails() {
        let t = sampleTransaction()
        #expect(!t.matches(searchTerms: searchTerms("apotheke")))
    }
}

import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct CurrencyTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    @Test func foreignSummariesGroupByCurrencyWithImpliedRate() throws {
        let chf = Account(name: "AMEX", institution: "X", currencyCode: "CHF")
        ctx.insert(chf)

        func add(_ amountCHF: String, _ orig: String, _ ccy: String) {
            let t = Transaction(descriptionText: "x", amount: Decimal(string: amountCHF)!,
                                originalAmount: Decimal(string: orig)!, originalCurrency: ccy)
            t.account = chf
            ctx.insert(t)
        }
        add("-64.00", "-59.90", "EUR")     // deducted 64 CHF for 59.90 EUR
        add("-8.30", "-9.10", "USD")       // deducted 8.30 CHF for 9.10 USD
        add("-42.50", "-42.50", "CHF")     // domestic → excluded
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let summaries = Analytics.foreignSummaries(all)
        #expect(summaries.count == 2)

        let eur = try #require(summaries.first { $0.currency == "EUR" })
        #expect(eur.spentOriginal == Decimal(string: "59.9"))
        #expect(eur.deductedAccount == Decimal(string: "64"))
        #expect(eur.accountCurrency == "CHF")
        // rate = 64 / 59.9 ≈ 1.0684
        #expect(eur.impliedRate > Decimal(string: "1.06")! && eur.impliedRate < Decimal(string: "1.07")!)

        // domestic CHF transaction is not treated as foreign
        #expect(summaries.contains { $0.currency == "CHF" } == false)
    }
}

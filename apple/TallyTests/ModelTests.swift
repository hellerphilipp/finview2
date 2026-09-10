import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct ModelTests {

    // Hold the container for the whole test — returning only `.mainContext`
    // would let the ModelContainer deallocate and orphan the context.
    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    @Test func seedingCreatesSwisscardProfileAndCategories() throws {
        Seeder.seedIfNeeded(ctx)

        let profiles = try ctx.fetch(FetchDescriptor<ImportProfile>())
        #expect(profiles.contains { $0.name == "Swisscard" })
        #expect(profiles.first { $0.name == "Swisscard" }?.specYAML.contains("row[5]") == true)

        let categories = try ctx.fetch(FetchDescriptor<SpendingCategory>())
        #expect(categories.contains { $0.name == "Groceries" })
        #expect(categories.contains { $0.name == "Supermarket" && $0.parent?.name == "Groceries" })
    }

    @Test func seedingIsIdempotent() throws {
        Seeder.seedIfNeeded(ctx)
        let firstCount = try ctx.fetch(FetchDescriptor<SpendingCategory>()).count
        Seeder.seedIfNeeded(ctx)
        let secondCount = try ctx.fetch(FetchDescriptor<SpendingCategory>()).count
        #expect(firstCount == secondCount)
        #expect(try ctx.fetch(FetchDescriptor<ImportProfile>()).count == 1)
    }

    @Test func transactionRelationshipsAndStatus() throws {
        let account = Account(name: "Swisscard Credit", institution: "Swisscard", currencyCode: "CHF")
        let cat = SpendingCategory(name: "Groceries")
        ctx.insert(account)
        ctx.insert(cat)

        let tx = Transaction(date: .now, descriptionText: "COOP", amount: Decimal(string: "-42.5")!,
                             originalAmount: Decimal(string: "-42.5")!, originalCurrency: "CHF")
        tx.account = account
        tx.category = cat
        ctx.insert(tx)
        try ctx.save()

        #expect(tx.status == .pending)
        tx.status = .confirmed
        #expect(tx.statusRaw == "confirmed")
        #expect(account.txs.count == 1)
        #expect(tx.isForeignCurrency == false)

        let eur = Transaction(descriptionText: "Amazon", amount: Decimal(string: "-50")!,
                              originalAmount: Decimal(string: "-45")!, originalCurrency: "EUR")
        eur.account = account
        ctx.insert(eur)
        #expect(eur.isForeignCurrency == true)
    }
}

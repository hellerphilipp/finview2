import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct AutoTaggerTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    @Test func merchantKeyExtractsParenthetical() {
        #expect(AutoTagger.merchantKey(from: "COOP Zurich (COOP Store)") == "COOP Store")
        #expect(AutoTagger.merchantKey(from: "Merchant B") == "Merchant B")
    }

    @Test func learnThenSuggestSameMerchant() throws {
        let groceries = SpendingCategory(name: "Groceries")
        ctx.insert(groceries)

        AutoTagger.learn(description: "COOP Zurich (COOP Store)", category: groceries, in: ctx)
        try ctx.save()

        let merchants = try ctx.fetch(FetchDescriptor<Merchant>())
        #expect(merchants.count == 1)

        // A different transaction from the same merchant should be suggested.
        let suggestion = AutoTagger.suggest(for: "COOP Basel (COOP Store)", merchants: merchants)
        #expect(suggestion?.name == "Groceries")
    }

    @Test func suggestReturnsNilWhenUnknown() throws {
        let merchants = try ctx.fetch(FetchDescriptor<Merchant>())
        #expect(AutoTagger.suggest(for: "Totally New Shop", merchants: merchants) == nil)
    }

    @Test func learnIsIdempotentPerMerchant() throws {
        let dining = SpendingCategory(name: "Dining")
        ctx.insert(dining)
        AutoTagger.learn(description: "Lunch (Starbucks)", category: dining, in: ctx)
        AutoTagger.learn(description: "Coffee (Starbucks)", category: dining, in: ctx)
        try ctx.save()
        let merchants = try ctx.fetch(FetchDescriptor<Merchant>())
        #expect(merchants.count == 1)               // same merchant, not duplicated
        #expect(merchants[0].patterns.count == 1)   // same key not re-added
    }
}

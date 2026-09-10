import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct AnalyticsTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func account() -> Account {
        let a = Account(name: "Card", institution: "Bank", currencyCode: "CHF")
        ctx.insert(a); return a
    }

    private func tx(_ acc: Account, _ amount: String, _ date: Date, category: SpendingCategory? = nil) {
        let t = Transaction(date: date, descriptionText: "x", amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: "CHF")
        t.account = acc
        t.category = category
        t.importedAt = date
        ctx.insert(t)
    }

    @Test func balanceSumsActiveAmounts() throws {
        let a = account()
        tx(a, "-42.50", day(2025, 1, 15))
        tx(a, "-20.00", day(2025, 1, 16))
        tx(a, "100.00", day(2025, 1, 17))
        try ctx.save()
        #expect(Analytics.balance(of: a) == Decimal(string: "37.5"))
    }

    @Test func stalenessDependsOnLastActivity() throws {
        let a = account()
        tx(a, "-10.00", day(2025, 1, 1))
        try ctx.save()
        #expect(Analytics.isStale(a, asOf: day(2025, 3, 1), days: 35) == true)
        #expect(Analytics.isStale(a, asOf: day(2025, 1, 10), days: 35) == false)
    }

    @Test func spendingByCategoryRollsUpToParent() throws {
        let a = account()
        let groceries = SpendingCategory(name: "Groceries")
        let supermarket = SpendingCategory(name: "Supermarket", parent: groceries)
        ctx.insert(groceries); ctx.insert(supermarket)
        tx(a, "-30.00", day(2025, 1, 5), category: supermarket)
        tx(a, "-10.00", day(2025, 1, 6), category: groceries)
        tx(a, "-5.00", day(2025, 1, 7))                     // uncategorized
        try ctx.save()

        let byCat = Analytics.spendingByCategory(a.txs)
        #expect(byCat.first?.name == "Groceries")
        #expect(byCat.first?.amount == Decimal(string: "40"))
        #expect(byCat.contains { $0.name == "Uncategorized" && $0.amount == Decimal(string: "5") })
    }

    @Test func monthlyCategorySpendingBuckets() throws {
        let a = account()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        tx(a, "-10.00", day(2025, 1, 5))
        tx(a, "-20.00", day(2025, 1, 25))
        tx(a, "-30.00", day(2025, 2, 3))
        try ctx.save()
        let monthly = Analytics.monthlyCategorySpending(a.txs, calendar: cal)
        // Two months for "Uncategorized"
        #expect(monthly.count == 2)
        #expect(monthly.first?.amount == Decimal(string: "30"))   // Jan total
    }

    @Test func openingBalanceCountsInBalanceButNotSpending() throws {
        let a = account()
        let opening = Transaction(date: day(2025, 1, 1), descriptionText: "Starting balance",
                                  amount: Decimal(string: "1000")!, originalAmount: Decimal(string: "1000")!,
                                  originalCurrency: "CHF", status: .confirmed)
        opening.isOpeningBalance = true
        opening.account = a
        ctx.insert(opening)
        tx(a, "-40.00", day(2025, 1, 5))
        try ctx.save()

        #expect(Analytics.balance(of: a) == Decimal(string: "960"))         // 1000 − 40
        #expect(Analytics.spending(a.txs, since: day(2025, 1, 1)) == Decimal(string: "40"))
    }

    @Test func workGroupingExcludeAndSeparate() throws {
        let a = account()
        let dining = SpendingCategory(name: "Dining")
        ctx.insert(dining)
        let work = Transaction(date: day(2025, 1, 5), descriptionText: "work",
                               amount: Decimal(string: "-50")!, originalAmount: Decimal(string: "-50")!,
                               originalCurrency: "CHF")
        work.account = a; work.category = dining; work.isWorkExpense = true
        ctx.insert(work)
        tx(a, "-30.00", day(2025, 1, 6), category: dining)
        try ctx.save()

        let excluded = Analytics.spendingByCategory(a.txs) { $0.isWorkExpense ? nil : Analytics.defaultCategoryName($0) }
        #expect(excluded.first { $0.name == "Dining" }?.amount == Decimal(string: "30"))

        let separate = Analytics.spendingByCategory(a.txs) { $0.isWorkExpense ? "Work" : Analytics.defaultCategoryName($0) }
        #expect(separate.first { $0.name == "Work" }?.amount == Decimal(string: "50"))
        #expect(separate.first { $0.name == "Dining" }?.amount == Decimal(string: "30"))
    }
}

import Foundation
import SwiftData

/// Seeds an in-memory store with representative multi-account data. Used only
/// for UI verification screenshots (activated by `TALLY_UITEST=1`); never runs
/// in the shipping app.
enum DemoData {
    @MainActor
    static func seed(_ ctx: ModelContext) {
        Seeder.seedIfNeeded(ctx)
        let cats = (try? ctx.fetch(FetchDescriptor<SpendingCategory>())) ?? []
        func cat(_ name: String) -> SpendingCategory? { cats.first { $0.name == name } }

        let current = Account(name: "Current", institution: "PostFinance", currencyCode: "CHF", colorHex: "#4C8BF5")
        let savings = Account(name: "Savings", institution: "PostFinance", currencyCode: "CHF", colorHex: "#34C759")
        let amex = Account(name: "AMEX", institution: "Swisscard", currencyCode: "CHF", colorHex: "#FF9500")
        let expenses = Account(name: "Expenses", institution: "Work", currencyCode: "CHF", colorHex: "#AF52DE")
        expenses.isExpenseAccount = true
        [current, savings, amex, expenses].forEach { ctx.insert($0) }

        func add(_ acc: Account, _ desc: String, _ amount: String, daysAgo: Int,
                 category: SpendingCategory? = nil, status: TransactionStatus = .confirmed,
                 work: Bool = false, origCurrency: String = "CHF", origAmount: String? = nil) {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            let tx = Transaction(date: date, descriptionText: desc, rawDescription: desc,
                                 amount: Decimal(string: amount)!,
                                 originalAmount: Decimal(string: origAmount ?? amount)!,
                                 originalCurrency: origCurrency, status: status)
            tx.account = acc
            tx.category = category
            tx.isWorkExpense = work
            tx.importedAt = date
            ctx.insert(tx)
        }

        // A cross-account transfer (left ungrouped → shows as a suggested match).
        add(current, "Transfer to Savings (Savings)", "-2000.00", daysAgo: 8)
        add(savings, "Transfer from Current (Current)", "2000.00", daysAgo: 8)

        // Everyday spending across a few months, categorized.
        add(current, "COOP Zurich (COOP Store)", "-42.50", daysAgo: 5, category: cat("Supermarket"))
        add(current, "Migros Bahnhof (Migros)", "-23.90", daysAgo: 20, category: cat("Supermarket"))
        add(amex, "Dinner (Kle Restaurant)", "-88.00", daysAgo: 12, category: cat("Restaurants"))
        add(amex, "Starbucks NYC (Starbucks)", "-8.30", daysAgo: 40, category: cat("Coffee"), origCurrency: "USD", origAmount: "-9.10")
        add(current, "SBB Mobile (SBB)", "-12.40", daysAgo: 33, category: cat("Public Transit"))
        add(current, "Rent October (Immobilien AG)", "-1850.00", daysAgo: 27, category: cat("Rent"))
        add(amex, "Amazon.de (Amazon)", "-64.00", daysAgo: 55, category: cat("Electronics"), origCurrency: "EUR", origAmount: "-59.90")

        // A monthly subscription → recurring detection.
        for i in 0..<4 {
            add(amex, "Netflix.com (Netflix)", "-19.90", daysAgo: 10 + i * 30, category: cat("Streaming"))
        }

        // Work expenses: two paid on cards and tagged work. One was posted to
        // the expense account (matched); two were not (missing / unclaimed).
        add(amex, "Team dinner (Kle Restaurant)", "-88.00", daysAgo: 12, category: cat("Restaurants"), work: true)
        add(expenses, "Team dinner reimbursement", "88.00", daysAgo: 6)     // posted line item → matches
        add(amex, "Client lunch (Bistro Central)", "-45.00", daysAgo: 9, category: cat("Restaurants"), work: true)   // not expensed
        add(current, "Taxi to client (Uber)", "-32.50", daysAgo: 7, category: cat("Taxi"), work: true)               // not expensed

        // A couple pending, uncategorized items to review.
        add(amex, "Denner (Denner)", "-31.20", daysAgo: 2, status: .pending)
        add(current, "Apotheke (Amavita)", "-18.60", daysAgo: 3, status: .pending)

        try? ctx.save()
    }
}

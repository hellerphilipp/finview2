import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct ExpenseReconcilerTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func account(_ name: String, expense: Bool = false) -> Account {
        let a = Account(name: name, institution: "X", currencyCode: "CHF")
        a.isExpenseAccount = expense
        ctx.insert(a); return a
    }

    @discardableResult
    private func tx(_ acc: Account, _ amount: String, daysAgo: Int, work: Bool = false) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let t = Transaction(date: date, descriptionText: "x", amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: "CHF")
        t.account = acc
        t.isWorkExpense = work
        ctx.insert(t); return t
    }

    @Test func noExpenseAccountYieldsEmpty() throws {
        let card = account("Card")
        tx(card, "-20.00", daysAgo: 3, work: true)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let r = ExpenseReconciler.reconcile(transactions: all, accounts: accounts)
        #expect(r.expenseAccount == nil)
        #expect(r.missing.isEmpty)
    }

    @Test func matchedWhenLineItemExists() throws {
        let card = account("Card")
        let expense = account("Expenses", expense: true)
        tx(card, "-20.00", daysAgo: 10, work: true)       // work charge
        tx(expense, "20.00", daysAgo: 3)                    // posted line item (+)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let r = ExpenseReconciler.reconcile(transactions: all, accounts: accounts)
        #expect(r.matchedCount == 1)
        #expect(r.missing.isEmpty)
    }

    @Test func flagsMissingWorkCharge() throws {
        let card = account("Card")
        _ = account("Expenses", expense: true)
        tx(card, "-88.00", daysAgo: 5, work: true)          // never expensed
        tx(card, "-30.00", daysAgo: 6, work: false)         // not work → ignored
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let r = ExpenseReconciler.reconcile(transactions: all, accounts: accounts)
        #expect(r.missing.count == 1)
        #expect(r.missing.first?.amount == Decimal(string: "-88"))
        #expect(r.missingTotal == Decimal(string: "88"))
    }

    @Test func oneLineItemMatchesOnlyOneOfTwoEqualCharges() throws {
        let card = account("Card")
        let expense = account("Expenses", expense: true)
        tx(card, "-20.00", daysAgo: 12, work: true)
        tx(card, "-20.00", daysAgo: 10, work: true)
        tx(expense, "20.00", daysAgo: 2)                    // only one line item
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let r = ExpenseReconciler.reconcile(transactions: all, accounts: accounts)
        #expect(r.matchedCount == 1)
        #expect(r.missing.count == 1)
    }

    @Test func matchedLineItemInheritsChargeCategory() throws {
        let card = account("Card")
        _ = account("Expenses", expense: true)
        let dining = SpendingCategory(name: "Dining")
        ctx.insert(dining)

        let charge = tx(card, "-88.00", daysAgo: 10, work: true)
        charge.category = dining
        let expenseAccount = try ctx.fetch(FetchDescriptor<Account>()).first { $0.isExpenseAccount }!
        let line = Transaction(descriptionText: "reimb", amount: Decimal(string: "88.00")!,
                               originalAmount: Decimal(string: "88.00")!, originalCurrency: "CHF")
        line.account = expenseAccount
        ctx.insert(line)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let r = ExpenseReconciler.reconcile(transactions: all, accounts: accounts)
        #expect(r.matched.count == 1)
        #expect(line.category == nil)

        let updated = ExpenseReconciler.inheritCategories(from: r, in: ctx)
        #expect(updated == 1)
        #expect(line.category?.name == "Dining")
    }
}

import Testing
import Foundation
import SwiftData

@MainActor
@Suite(.serialized)
struct LinkServiceTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private func account(_ name: String, _ currency: String = "CHF") -> Account {
        let a = Account(name: name, institution: "Bank", currencyCode: currency)
        ctx.insert(a); return a
    }

    @discardableResult
    private func tx(_ acc: Account, _ amount: String, category: SpendingCategory? = nil) -> Transaction {
        let t = Transaction(date: .now, descriptionText: "x", amount: Decimal(string: amount)!,
                            originalAmount: Decimal(string: amount)!, originalCurrency: acc.currencyCode)
        t.account = acc; t.category = category; ctx.insert(t); return t
    }

    // MARK: canLinkRefund

    @Test func acceptsOneChargePlusOneRefund() {
        let card = account("Card")
        #expect(LinkService.canLinkRefund([tx(card, "-250"), tx(card, "50")]))
    }

    @Test func acceptsOneChargePlusMultipleRefunds() {
        let card = account("Card")
        #expect(LinkService.canLinkRefund([tx(card, "-250"), tx(card, "50"), tx(card, "30")]))
    }

    @Test func acceptsCrossAccountRefund() {
        let card = account("Card"), current = account("Current")
        #expect(LinkService.canLinkRefund([tx(card, "-100"), tx(current, "50")]))
    }

    @Test func rejectsInvalidRefundShapes() {
        let card = account("Card"), eur = account("EUR", "EUR")
        #expect(!LinkService.canLinkRefund([tx(card, "-100")]))                    // single row
        #expect(!LinkService.canLinkRefund([tx(card, "-100"), tx(card, "-50")]))   // two charges, no refund
        #expect(!LinkService.canLinkRefund([tx(card, "50"), tx(card, "30")]))      // no charge
        #expect(!LinkService.canLinkRefund([tx(card, "-100"), tx(eur, "50")]))     // mixed currency
        #expect(!LinkService.canLinkRefund([tx(card, "-100"), tx(card, "50"), tx(card, "-20")])) // 2 charges
    }

    @Test func rejectsAlreadyLinked() {
        let card = account("Card")
        let charge = tx(card, "-100"), refund = tx(card, "50")
        LinkService.link([charge, refund], kind: .refund, in: ctx)
        #expect(!LinkService.canLinkRefund([charge, tx(card, "40")]))
    }

    // MARK: link forces one shared category + confirms

    @Test func refundAdoptsChargeCategoryAndKeepsStatus() throws {
        let card = account("Card")
        let shop = SpendingCategory(name: "Shopping", kind: .spending); ctx.insert(shop)
        let charge = tx(card, "-250", category: shop)     // pending by default
        let refund = tx(card, "50")                       // uncategorized, pending
        LinkService.link([charge, refund], kind: .refund, in: ctx)

        #expect(refund.category === shop)                 // forced to the charge's category
        #expect(charge.linkGroupID != nil && charge.linkGroupID == refund.linkGroupID)
        #expect(charge.linkKind == .refund && refund.linkKind == .refund)
        // Linking must not auto-review: status is left untouched.
        #expect(charge.status == .pending && refund.status == .pending)
    }

    @Test func linkingPreservesAnAlreadyConfirmedStatus() throws {
        let card = account("Card")
        let charge = tx(card, "-250"); charge.status = .confirmed
        let refund = tx(card, "50")                        // pending
        LinkService.link([charge, refund], kind: .refund, in: ctx)
        #expect(charge.status == .confirmed && refund.status == .pending)
    }

    // MARK: propagateCategory keeps the group in sync

    @Test func recategorizingOneMemberUpdatesWholeGroup() throws {
        let card = account("Card")
        let shop = SpendingCategory(name: "Shopping", kind: .spending)
        let dining = SpendingCategory(name: "Dining", kind: .spending)
        ctx.insert(shop); ctx.insert(dining)
        let charge = tx(card, "-250", category: shop)
        let refund = tx(card, "50", category: shop)
        LinkService.link([charge, refund], kind: .refund, in: ctx)
        let gid = try #require(charge.linkGroupID)

        LinkService.propagateCategory(dining, groupID: gid,
                                      among: [charge, refund], context: ctx)
        #expect(charge.category === dining && refund.category === dining)
    }
}

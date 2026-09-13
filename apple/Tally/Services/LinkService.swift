import Foundation
import SwiftData

/// Links related transactions into one group (a transfer's two legs, or a charge
/// with its refund(s)). All members of a group share one `linkGroupID` and one
/// `linkKind`. Reports net a group's signed amounts into its shared category, so
/// the *kind* only drives validation and display, never the math.
enum LinkService {

    /// Whether a selection forms a valid **refund** link: exactly one charge
    /// (negative) and one or more refunds (positive), all in the same currency,
    /// none already linked or an opening balance. Accounts may differ (e.g. a
    /// card charge reimbursed into a current account). The day gap is ignored.
    static func canLinkRefund(_ txs: [Transaction]) -> Bool {
        guard txs.count >= 2 else { return false }
        guard txs.allSatisfy({ $0.linkGroupID == nil && !$0.isOpeningBalance }) else { return false }
        let charges = txs.filter { $0.amount < 0 }
        let refunds = txs.filter { $0.amount > 0 }
        guard charges.count == 1, refunds.count == txs.count - 1 else { return false }
        return Set(txs.compactMap { $0.account?.currencyCode }).count == 1
    }

    /// The category a freshly linked group adopts: the charge's (the most-negative
    /// leg), so a refund inherits the purchase's bucket. `nil` if uncategorized.
    static func sharedCategory(for txs: [Transaction]) -> SpendingCategory? {
        txs.min { $0.amount < $1.amount }?.category
    }

    /// Link a selection as one group of the given kind: set the shared id and
    /// kind and force every member to the group's shared category. Each row keeps
    /// its existing review status — linking is not a review action. Callers should
    /// gate on the matching `canLink…` check.
    @MainActor
    static func link(_ txs: [Transaction], kind: LinkKind, in context: ModelContext) {
        guard txs.count >= 2 else { return }
        let gid = UUID()
        let category = sharedCategory(for: txs)
        for tx in txs {
            tx.linkGroupID = gid
            tx.linkKind = kind
            tx.category = category
        }
        try? context.save()
    }

    /// Propagate a category to every member of a link group, preserving the
    /// "one shared category" invariant when the user recategorizes any member.
    @MainActor
    static func propagateCategory(_ category: SpendingCategory?, groupID: UUID,
                                  among txs: [Transaction], context: ModelContext) {
        for tx in txs where tx.linkGroupID == groupID {
            tx.category = category
        }
        try? context.save()
    }

    /// Remove a group's link from all its members.
    @MainActor
    static func unlink(groupID: UUID, in txs: [Transaction], context: ModelContext) {
        for tx in txs where tx.linkGroupID == groupID {
            tx.linkGroupID = nil
        }
        try? context.save()
    }
}

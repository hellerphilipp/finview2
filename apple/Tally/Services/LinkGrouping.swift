import Foundation

/// Pure display helpers for linked transactions: keep a group's members adjacent
/// in the table regardless of the active sort, and re-include a group member that
/// a filter/search would otherwise hide so a pair never shows only one side.
enum LinkGrouping {

    /// Reorder rows so every link group's members sit together, anchored at the
    /// group's first appearance in `txs` (i.e. its position under the active
    /// sort). Within a group the charge (most negative) leads, then refunds.
    static func orderedForDisplay(_ txs: [Transaction]) -> [Transaction] {
        let grouped = Dictionary(grouping: txs.filter { $0.linkGroupID != nil }) { $0.linkGroupID! }
        var result: [Transaction] = []
        var placed = Set<UUID>()
        for tx in txs {
            guard !placed.contains(tx.id) else { continue }
            if let gid = tx.linkGroupID, let members = grouped[gid] {
                for m in members.sorted(by: memberOrder) where placed.insert(m.id).inserted {
                    result.append(m)
                }
            } else {
                result.append(tx)
                placed.insert(tx.id)
            }
        }
        return result
    }

    /// Given the account-scoped universe and a match predicate (status + search),
    /// return the rows to show plus the ids to render dimmed. Any group with at
    /// least one matching member contributes *all* its members; the non-matching
    /// ones are the "context" ids shown in gray.
    static func expandWithContext(_ universe: [Transaction],
                                  matches: (Transaction) -> Bool) -> (visible: [Transaction], contextIDs: Set<UUID>) {
        let matchedGroups = Set(universe.filter(matches).compactMap { $0.linkGroupID })
        var contextIDs = Set<UUID>()
        let visible = universe.filter { tx in
            if matches(tx) { return true }
            if let gid = tx.linkGroupID, matchedGroups.contains(gid) {
                contextIDs.insert(tx.id)
                return true
            }
            return false
        }
        return (visible, contextIDs)
    }

    private static func memberOrder(_ a: Transaction, _ b: Transaction) -> Bool {
        if a.amount != b.amount { return a.amount < b.amount }
        return a.date < b.date
    }
}

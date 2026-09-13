import Foundation
import SwiftData

/// Finds cross-account transfers: an outgoing charge on one account matched by
/// an equal, opposite credit on another account within a few days
/// (e.g. −2000 CHF on Current ↔ +2000 CHF on Savings).
enum TransferMatcher {

    struct Candidate: Identifiable {
        let id = UUID()
        let outgoing: Transaction   // negative amount
        let incoming: Transaction   // positive amount
        let amount: Decimal         // magnitude (account currency)
        let currency: String
        let dayGap: Int
    }

    /// Suggest 1:1 transfer matches among not-yet-reviewed transactions.
    /// A leg is only eligible when it is still **pending** (not confirmed or
    /// rejected), not already grouped, not an opening balance, and either
    /// uncategorized or already filed under a transfer-kind category. Pairs must
    /// then share a currency, have equal-and-opposite amounts, sit on different
    /// accounts, and fall within `maxDayGap` days (default 10). Manual linking
    /// via `canLink` deliberately ignores the day gap so a user can link a pair
    /// that is further apart.
    static func candidates(_ txs: [Transaction], maxDayGap: Int = 10,
                           calendar: Calendar = .current) -> [Candidate] {
        let eligible = txs.filter { isEligibleLeg($0) }
        let outgoings = eligible.filter { $0.amount < 0 }
        let incomings = eligible.filter { $0.amount > 0 }

        // Build all valid pairings, then greedily pick disjoint ones by best gap.
        var pairs: [Candidate] = []
        for out in outgoings {
            for inc in incomings {
                guard out.account?.id != inc.account?.id else { continue }
                guard out.account?.currencyCode == inc.account?.currencyCode else { continue }
                guard -out.amount == inc.amount else { continue }
                let gap = abs(calendar.dateComponents([.day], from: out.date, to: inc.date).day ?? Int.max)
                guard gap <= maxDayGap else { continue }
                pairs.append(Candidate(outgoing: out, incoming: inc, amount: inc.amount,
                                       currency: inc.account?.currencyCode ?? "", dayGap: gap))
            }
        }

        pairs.sort { $0.dayGap < $1.dayGap }
        var usedOut = Set<UUID>(), usedIn = Set<UUID>()
        var result: [Candidate] = []
        for c in pairs {
            guard !usedOut.contains(c.outgoing.id), !usedIn.contains(c.incoming.id) else { continue }
            usedOut.insert(c.outgoing.id); usedIn.insert(c.incoming.id)
            result.append(c)
        }
        return result.sorted { $0.outgoing.date > $1.outgoing.date }
    }

    /// Whether an arbitrary selection forms a valid transfer pair, using the
    /// same rules as automatic matching: exactly two transactions, on different
    /// accounts, in the same currency, with equal-and-opposite amounts, and
    /// neither already part of a transfer.
    ///
    /// - Note: the same-currency requirement is a current limitation — a real
    ///   cross-currency transfer (e.g. −100 CHF ↔ +108 EUR) can't be linked
    ///   yet. Revisit if/when FX transfers need support.
    static func canLink(_ txs: [Transaction]) -> Bool {
        guard txs.count == 2 else { return false }
        let a = txs[0], b = txs[1]
        guard a.linkGroupID == nil, b.linkGroupID == nil else { return false }
        guard let accA = a.account?.id, let accB = b.account?.id, accA != accB else { return false }
        guard a.account?.currencyCode == b.account?.currencyCode else { return false }
        guard a.amount != 0, a.amount == -b.amount else { return false }
        return true
    }

    /// Link a hand-picked pair as a confirmed transfer. No-op unless
    /// `canLink(txs)` — callers should gate the action on that.
    @MainActor
    static func link(_ txs: [Transaction], in context: ModelContext) {
        guard canLink(txs) else { return }
        LinkService.link(txs, kind: .transfer, in: context)
    }

    /// A transaction the auto-matcher may propose as a transfer leg: still
    /// pending review, ungrouped, not an opening balance, and either
    /// uncategorized or already under a transfer-kind category.
    private static func isEligibleLeg(_ tx: Transaction) -> Bool {
        guard tx.status == .pending else { return false }
        guard tx.linkGroupID == nil else { return false }
        guard !tx.isOpeningBalance else { return false }
        if let kind = tx.category?.kind { return kind == .transfer }
        return true   // uncategorized
    }

    /// Link two transactions as a confirmed transfer (shared group id).
    @MainActor
    static func confirm(_ candidate: Candidate, in context: ModelContext) {
        link([candidate.outgoing, candidate.incoming], in: context)
    }

    /// Remove the transfer link from a group (both sides).
    @MainActor
    static func unlink(groupID: UUID, in txs: [Transaction], context: ModelContext) {
        LinkService.unlink(groupID: groupID, in: txs, context: context)
    }

    /// Group confirmed transfers by their shared id for display.
    static func confirmedGroups(_ txs: [Transaction]) -> [(id: UUID, transactions: [Transaction])] {
        var groups: [UUID: [Transaction]] = [:]
        for tx in txs {
            if let gid = tx.linkGroupID { groups[gid, default: []].append(tx) }
        }
        return groups
            .map { (id: $0.key, transactions: $0.value.sorted { $0.amount < $1.amount }) }
            .sorted { ($0.transactions.first?.date ?? .distantPast) > ($1.transactions.first?.date ?? .distantPast) }
    }
}

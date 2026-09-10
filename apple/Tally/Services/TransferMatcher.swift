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

    /// Suggest 1:1 transfer matches among not-yet-grouped transactions.
    /// Same currency + equal magnitude + different accounts + within `maxDayGap`.
    static func candidates(_ txs: [Transaction], maxDayGap: Int = 3,
                           calendar: Calendar = .current) -> [Candidate] {
        let eligible = txs.filter { $0.status != .rejected && $0.transferGroupID == nil }
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

    /// Link two transactions as a confirmed transfer (shared group id).
    @MainActor
    static func confirm(_ candidate: Candidate, in context: ModelContext) {
        let gid = UUID()
        for tx in [candidate.outgoing, candidate.incoming] {
            tx.transferGroupID = gid
            tx.status = .confirmed
        }
        try? context.save()
    }

    /// Remove the transfer link from a group (both sides).
    @MainActor
    static func unlink(groupID: UUID, in txs: [Transaction], context: ModelContext) {
        for tx in txs where tx.transferGroupID == groupID {
            tx.transferGroupID = nil
        }
        try? context.save()
    }

    /// Group confirmed transfers by their shared id for display.
    static func confirmedGroups(_ txs: [Transaction]) -> [(id: UUID, transactions: [Transaction])] {
        var groups: [UUID: [Transaction]] = [:]
        for tx in txs {
            if let gid = tx.transferGroupID { groups[gid, default: []].append(tx) }
        }
        return groups
            .map { (id: $0.key, transactions: $0.value.sorted { $0.amount < $1.amount }) }
            .sorted { ($0.transactions.first?.date ?? .distantPast) > ($1.transactions.first?.date ?? .distantPast) }
    }
}

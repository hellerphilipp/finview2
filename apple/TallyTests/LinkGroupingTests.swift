import Testing
import Foundation
import SwiftData

/// Pure display helpers: keep a link group's members adjacent while sorting, and
/// pull an unmatched group member back in as context when a filter hides it.
@MainActor
@Suite(.serialized)
struct LinkGroupingTests {

    private func tx(_ amount: String, group: UUID? = nil, day: Int = 1) -> Transaction {
        var c = DateComponents(); c.year = 2025; c.month = 1; c.day = day
        let d = Calendar(identifier: .gregorian).date(from: c)!
        let t = Transaction(date: d, descriptionText: "x", amount: Decimal(string: amount)!)
        t.linkGroupID = group
        return t
    }

    @Test func clustersGroupMembersUnderTheirAnchor() {
        let g = UUID()
        let charge = tx("-250", group: g, day: 1)   // appears first
        let lone = tx("-40", day: 2)
        let refund = tx("50", group: g, day: 3)      // appears last

        let ordered = LinkGrouping.orderedForDisplay([charge, lone, refund])
        // Refund jumps up next to its charge; lone keeps trailing.
        #expect(ordered.map(\.id) == [charge.id, refund.id, lone.id])
    }

    @Test func withinGroupChargeComesBeforeRefunds() {
        let g = UUID()
        let refund = tx("50", group: g, day: 3)
        let charge = tx("-250", group: g, day: 1)
        // Even if the refund is listed first, the negative charge leads.
        let ordered = LinkGrouping.orderedForDisplay([refund, charge])
        #expect(ordered.map(\.id) == [charge.id, refund.id])
    }

    @Test func lonesKeepOrderWhenNoGroups() {
        let a = tx("-10", day: 1), b = tx("-20", day: 2)
        #expect(LinkGrouping.orderedForDisplay([a, b]).map(\.id) == [a.id, b.id])
    }

    @Test func contextPullsInUnmatchedPartner() {
        let g = UUID()
        let charge = tx("-250", group: g)
        let refund = tx("50", group: g)
        let other = tx("-40")

        // Only the charge matches the filter; the refund should ride along, dimmed.
        let (visible, contextIDs) = LinkGrouping.expandWithContext([charge, refund, other]) {
            $0.id == charge.id
        }
        #expect(Set(visible.map(\.id)) == [charge.id, refund.id])
        #expect(contextIDs == [refund.id])
    }

    @Test func groupWithNoMatchIsExcluded() {
        let g = UUID()
        let charge = tx("-250", group: g)
        let refund = tx("50", group: g)
        let (visible, contextIDs) = LinkGrouping.expandWithContext([charge, refund]) { _ in false }
        #expect(visible.isEmpty && contextIDs.isEmpty)
    }

    @Test func loneMatchHasNoContext() {
        let a = tx("-10")
        let (visible, contextIDs) = LinkGrouping.expandWithContext([a]) { _ in true }
        #expect(visible.map(\.id) == [a.id] && contextIDs.isEmpty)
    }
}

import SwiftUI
import SwiftData

struct TransfersView: View {
    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]

    private var suggestions: [TransferMatcher.Candidate] {
        TransferMatcher.candidates(transactions)
    }
    private var confirmed: [(id: UUID, transactions: [Transaction])] {
        TransferMatcher.confirmedGroups(transactions)
    }

    var body: some View {
        Group {
            if suggestions.isEmpty && confirmed.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "arrow.left.arrow.right",
                                       description: Text("When an outgoing charge on one account is matched by an equal credit on another within a few days, it shows up here."))
            } else {
                List {
                    if !suggestions.isEmpty {
                        Section("Suggested Matches") {
                            ForEach(suggestions) { candidate in
                                SuggestionRow(candidate: candidate) {
                                    TransferMatcher.confirm(candidate, in: context)
                                }
                            }
                        }
                    }
                    if !confirmed.isEmpty {
                        Section("Confirmed Transfers") {
                            ForEach(confirmed, id: \.id) { group in
                                ConfirmedRow(group: group.transactions) {
                                    TransferMatcher.unlink(groupID: group.id, in: transactions, context: context)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfers")
    }
}

private struct SuggestionRow: View {
    let candidate: TransferMatcher.Candidate
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leg(account: candidate.outgoing.account?.name ?? "—",
                date: candidate.outgoing.date, amount: candidate.outgoing.amount,
                currency: candidate.currency)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            leg(account: candidate.incoming.account?.name ?? "—",
                date: candidate.incoming.date, amount: candidate.incoming.amount,
                currency: candidate.currency)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string(candidate.amount, currency: candidate.currency)).bold().monospacedDigit()
                Text(candidate.dayGap == 0 ? "same day" : "\(candidate.dayGap)d apart")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Confirm", action: onConfirm).buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func leg(account: String, date: Date, amount: Decimal, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(account).font(.subheadline.bold())
            Text(DateText.string(date)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ConfirmedRow: View {
    let group: [Transaction]
    let onUnlink: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.compactMap { $0.account?.name }.joined(separator: " ↔ "))
                    .font(.subheadline.bold())
                if let first = group.first {
                    Text(DateText.string(first.date)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let amount = group.first(where: { $0.amount > 0 })?.amount, let cur = group.first?.account?.currencyCode {
                Text(Money.string(amount, currency: cur)).monospacedDigit().foregroundStyle(.secondary)
            }
            Button("Unlink", role: .destructive, action: onUnlink).buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

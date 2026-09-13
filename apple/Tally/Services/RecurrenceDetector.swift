import Foundation

/// Detects recurring transactions (subscriptions, rent, etc.) by grouping on
/// merchant and looking for a regular cadence.
enum RecurrenceDetector {

    enum Cadence: String, Sendable {
        case monthly, quarterly, yearly
        var label: String { rawValue.capitalized }
        var approxDays: Int {
            switch self {
            case .monthly: 30
            case .quarterly: 91
            case .yearly: 365
            }
        }
    }

    struct Series: Identifiable, Sendable {
        let id = UUID()
        let merchant: String
        let cadence: Cadence
        let averageAmount: Decimal
        let currency: String
        let occurrences: Int
        let lastDate: Date
        let nextExpected: Date
    }

    /// Group charge transactions by merchant key and report those with a
    /// consistent monthly/quarterly/yearly cadence over 3+ occurrences.
    static func detect(_ txs: [Transaction], calendar: Calendar = .current) -> [Series] {
        let active = txs.filter { $0.amount < 0 }
        var groups: [String: [Transaction]] = [:]
        for tx in active {
            groups[AutoTagger.merchantKey(from: tx.descriptionText), default: []].append(tx)
        }

        var result: [Series] = []
        for (merchant, group) in groups where group.count >= 3 {
            let sorted = group.sorted { $0.date < $1.date }
            let gaps = zip(sorted.dropFirst(), sorted).map {
                calendar.dateComponents([.day], from: $1.date, to: $0.date).day ?? 0
            }
            guard let cadence = cadence(forMedianGap: median(gaps)) else { continue }

            let amounts = sorted.map(\.amount)
            let avg = amounts.reduce(Decimal.zero, +) / Decimal(amounts.count)
            guard amountsAreConsistent(amounts, average: avg) else { continue }

            let last = sorted.last!.date
            let next = calendar.date(byAdding: .day, value: cadence.approxDays, to: last) ?? last
            result.append(Series(
                merchant: merchant,
                cadence: cadence,
                averageAmount: avg,
                currency: sorted.last!.account?.currencyCode ?? "",
                occurrences: sorted.count,
                lastDate: last,
                nextExpected: next
            ))
        }
        return result.sorted { $0.nextExpected < $1.nextExpected }
    }

    static func cadence(forMedianGap gap: Int) -> Cadence? {
        switch gap {
        case 25...35: .monthly
        case 80...100: .quarterly
        case 350...380: .yearly
        default: nil
        }
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Amounts count as consistent if each is within 15% of the average.
    private static func amountsAreConsistent(_ amounts: [Decimal], average: Decimal) -> Bool {
        let avg = abs((average as NSDecimalNumber).doubleValue)
        guard avg > 0 else { return false }
        return amounts.allSatisfy { a in
            let v = abs((a as NSDecimalNumber).doubleValue)
            return abs(v - avg) / avg <= 0.15
        }
    }
}

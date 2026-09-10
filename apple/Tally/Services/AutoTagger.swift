import Foundation
import SwiftData

/// Learns which category a merchant usually gets, and suggests categories for
/// new transactions based on that history.
enum AutoTagger {

    /// Extract a stable merchant key from a transaction description.
    /// Swisscard descriptions look like "Detail (Merchant)"; the parenthetical
    /// is the merchant, which is the most stable matching token.
    static func merchantKey(from description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.lastIndex(of: "("),
           let close = trimmed.lastIndex(of: ")"),
           open < close {
            let inner = trimmed[trimmed.index(after: open)..<close]
            let key = inner.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { return key }
        }
        return trimmed
    }

    /// Suggest a category for a description given known merchants.
    /// The longest matching pattern wins (most specific).
    static func suggest(for description: String, merchants: [Merchant]) -> SpendingCategory? {
        let haystack = description.lowercased()
        var best: (len: Int, category: SpendingCategory)?
        for merchant in merchants {
            guard let category = merchant.defaultCategory else { continue }
            for pattern in merchant.patterns {
                let p = pattern.lowercased()
                guard !p.isEmpty, haystack.contains(p) else { continue }
                if best == nil || p.count > best!.len {
                    best = (p.count, category)
                }
            }
        }
        return best?.category
    }

    /// Record that a transaction's description maps to a category, so future
    /// transactions from the same merchant can be auto-suggested. Upserts a
    /// `Merchant` keyed by its canonical name.
    @MainActor
    static func learn(description: String, category: SpendingCategory, in context: ModelContext) {
        let key = merchantKey(from: description)
        guard !key.isEmpty else { return }

        let merchants = (try? context.fetch(FetchDescriptor<Merchant>())) ?? []
        if let existing = merchants.first(where: { $0.canonicalName.caseInsensitiveCompare(key) == .orderedSame }) {
            existing.defaultCategory = category
            if !existing.patterns.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
                existing.patterns.append(key)
            }
        } else {
            let merchant = Merchant(canonicalName: key, patterns: [key], defaultCategory: category)
            context.insert(merchant)
        }
    }
}

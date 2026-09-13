import Foundation

/// Free-text search over the transaction ledger.
///
/// Kept as pure logic (no SwiftUI) so it can be unit-tested directly, mirroring
/// `StatusFilter.matches` in `Support/AppRouter.swift`. The view supplies a
/// query string; `searchTerms` tokenizes it and `matches(searchTerms:)` tests a
/// row against the tokens with all-terms-must-match semantics.

/// Split a raw query into lowercased, whitespace-separated terms. A blank query
/// yields `[]`, which `matches(searchTerms:)` treats as "matches everything".
func searchTerms(_ query: String) -> [String] {
    query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
}

extension Transaction {
    /// True when every term is contained in the row's searchable text. An empty
    /// term list (blank query) matches everything.
    func matches(searchTerms terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let haystack = searchHaystack.lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// All the text a search can match against: description, raw bank text, note,
    /// account name + currency, category path, merchant, tag names, the amount,
    /// and the date.
    ///
    /// Amount and date are formatted here (rather than reusing the display
    /// formatters in `Support/Formatting`) so this stays pure `Models`-layer
    /// logic. The amount is emitted *without* grouping separators so a query like
    /// "2000" still matches a value the ledger shows as "2'000.00".
    var searchHaystack: String {
        var parts: [String] = [
            descriptionText,
            rawDescription,
            note,
            accountName,
            account?.currencyCode ?? "",
            categorySortKey,
            merchant?.canonicalName ?? "",
            Self.amountText.string(from: amount as NSDecimalNumber) ?? "",
            Self.dateText.string(from: date),
        ]
        if let tags { parts.append(contentsOf: tags.map(\.name)) }
        return parts.joined(separator: " ")
    }

    private static let amountText: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateText: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

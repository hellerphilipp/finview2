import Foundation
import SwiftUI

enum Money {
    /// Format a Decimal as a currency string (e.g. "-42.50 CHF").
    static func string(_ value: Decimal, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "de_CH")
        return f.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }

    /// The grouped number only, no currency symbol (e.g. "-2'000.00").
    /// Use with a separate currency label for right-aligned ledger columns.
    static func amount(_ value: Decimal) -> String {
        amountFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_CH")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}

enum DateText {
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    static func string(_ date: Date) -> String { medium.string(from: date) }
}

extension Color {
    /// Create a Color from a "#RRGGBB" hex string. Falls back to gray.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = .gray; return }
        self = Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

import Foundation
import SwiftData
import ImportKit

enum Seeder {
    /// Seed the Swisscard import profile and a starter category tree the first
    /// time the app runs. Idempotent: safe to call on every launch.
    static func seedIfNeeded(_ context: ModelContext) {
        seedSwisscardProfile(context)
        seedStarterCategories(context)
        try? context.save()
    }

    private static func seedSwisscardProfile(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ImportProfile>())) ?? []
        guard !existing.contains(where: { $0.name == "Swisscard" }) else { return }
        guard let yaml = try? StatementImporter.swisscardSpecYAML() else { return }
        context.insert(ImportProfile(name: "Swisscard", specYAML: yaml, version: "1.0"))
    }

    private static func seedStarterCategories(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<SpendingCategory>())) ?? []
        guard existing.isEmpty else { return }

        // (name, colorHex, SF Symbol, kind, [subcategory names])
        let tree: [(String, String, String, CategoryKind, [String])] = [
            ("Groceries", "#34C759", "cart", .spending, ["Supermarket", "Bakery"]),
            ("Dining", "#FF9500", "fork.knife", .spending, ["Restaurants", "Coffee"]),
            ("Household", "#5AC8FA", "house", .spending, ["Rent", "Utilities", "Furniture"]),
            ("Transport", "#007AFF", "tram", .spending, ["Public Transit", "Fuel", "Taxi"]),
            ("Subscriptions", "#AF52DE", "repeat", .spending, ["Streaming", "Software"]),
            ("Gifts", "#FF2D55", "gift", .spending, []),
            ("Health", "#FF3B30", "cross.case", .spending, []),
            ("Shopping", "#FFCC00", "bag", .spending, ["Clothing", "Electronics"]),
            ("Income", "#30D158", "arrow.down.circle", .income, ["Salary", "Refunds"]),
            ("Transfers", "#8E8E93", "arrow.left.arrow.right", .transfer, []),
        ]

        for (index, entry) in tree.enumerated() {
            let (name, color, symbol, kind, subs) = entry
            let parent = SpendingCategory(name: name, colorHex: color, symbolName: symbol,
                                          kind: kind, sortOrder: index)
            context.insert(parent)
            for (subIndex, subName) in subs.enumerated() {
                let child = SpendingCategory(name: subName, colorHex: color, symbolName: symbol,
                                             kind: kind, sortOrder: subIndex, parent: parent)
                context.insert(child)
            }
        }
    }
}

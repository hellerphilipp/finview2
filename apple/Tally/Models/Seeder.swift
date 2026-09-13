import Foundation
import SwiftData
import ImportKit

enum Seeder {
    /// UserDefaults key recording which built-in spec names have already been
    /// offered, so a built-in the user *deletes* doesn't reappear on next launch
    /// while genuinely new bundled specs (added in future app versions) still seed.
    private static let seededBuiltinsKey = "seededBuiltinSpecNames"

    /// Seed the bundled import profiles and a starter category tree the first
    /// time the app runs. Idempotent: safe to call on every launch.
    /// `defaults` is injectable so tests don't touch the shared store.
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        seedBuiltinProfiles(context, defaults: defaults)
        seedStarterCategories(context)
        purgeRejectedTransactions(context)
        try? context.save()
    }

    /// One-time cleanup: the old "rejected" status is gone (a transaction is
    /// either confirmed or not), so delete any leftover rejected rows that were
    /// otherwise invisible in the UI.
    private static func purgeRejectedTransactions(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.statusRaw == "rejected" }
        )
        guard let rejected = try? context.fetch(descriptor), !rejected.isEmpty else { return }
        for tx in rejected { context.delete(tx) }
    }

    /// Pre-install every import spec shipped in ImportKit's bundle as an
    /// `ImportProfile`. Each built-in is seeded at most once (tracked in
    /// UserDefaults) so user deletions stick.
    private static func seedBuiltinProfiles(_ context: ModelContext, defaults: UserDefaults) {
        var seeded = Set(defaults.stringArray(forKey: seededBuiltinsKey) ?? [])
        let existing = (try? context.fetch(FetchDescriptor<ImportProfile>())) ?? []
        let existingNames = Set(existing.map(\.name))

        for yaml in StatementImporter.bundledSpecYAMLs() {
            guard let spec = try? ImportSpec(yaml: yaml) else { continue }
            let name = spec.name
            // Skip if we've offered it before or a same-named profile is present
            // (the latter migrates existing users who already have "Swisscard").
            if seeded.contains(name) || existingNames.contains(name) {
                seeded.insert(name)
                continue
            }
            context.insert(ImportProfile(name: name, specYAML: yaml, version: spec.version))
            seeded.insert(name)
        }
        defaults.set(Array(seeded), forKey: seededBuiltinsKey)
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

import Foundation
import SwiftData

enum Persistence {
    /// The full model schema for the app.
    static let schema = Schema([
        Account.self,
        Transaction.self,
        SpendingCategory.self,
        Merchant.self,
        Tag.self,
        ImportProfile.self,
        ImportBatch.self,
    ])

    /// Build the app's model container.
    ///
    /// Runs against a local on-disk (or in-memory) store. CloudKit sync is
    /// intentionally *not* enabled here: it requires an iCloud entitlement +
    /// a signing team. To enable it later, add the entitlement and pass
    /// `cloudKitDatabase: .automatic` to the `ModelConfiguration` below — the
    /// model is already designed to satisfy CloudKit's constraints.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

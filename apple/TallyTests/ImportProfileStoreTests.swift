import Testing
import Foundation
import SwiftData
import ImportKit

@MainActor
@Suite(.serialized)
struct ImportProfileStoreTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private let validYAML = """
    version: "2.0"
    name: TestBank
    parser:
      delimiter: ","
      skip_rows: 1
    mappings:
      timestamp: "row[0]"
      description: "row[1]"
      amount_original: "double(row[2])"
      currency_original: "row[3]"
      amount_in_account_currency: "double(row[2])"
    """

    @Test func makeProfileUsesSpecNameAndVersion() throws {
        let p = try ImportProfileStore.makeProfile(fromYAML: validYAML)
        #expect(p.name == "TestBank")
        #expect(p.version == "2.0")
        #expect(p.specYAML == validYAML)
    }

    @Test func makeProfileRejectsEmpty() {
        #expect(throws: (any Error).self) {
            try ImportProfileStore.makeProfile(fromYAML: "   \n  ")
        }
    }

    @Test func makeProfileRejectsMalformedYAML() {
        #expect(throws: (any Error).self) {
            try ImportProfileStore.makeProfile(fromYAML: "not: [valid: yaml")
        }
    }

    @Test func makeProfileRejectsBadCEL() {
        // Break the timestamp mapping into an uncompilable CEL expression.
        let bad = validYAML.replacingOccurrences(of: "\"row[0]\"", with: "\"row[\"")
        #expect(throws: (any Error).self) {
            try ImportProfileStore.makeProfile(fromYAML: bad)
        }
    }

    @Test func installInsertsProfile() throws {
        let p = try ImportProfileStore.install(yaml: validYAML, into: ctx)
        #expect(p.name == "TestBank")
        #expect(try ctx.fetch(FetchDescriptor<ImportProfile>()).count == 1)
    }

    @Test func installReplacesSameNameInPlace() throws {
        _ = try ImportProfileStore.install(yaml: validYAML, into: ctx)
        let updated = validYAML.replacingOccurrences(of: "version: \"2.0\"",
                                                     with: "version: \"3.0\"")
        let p = try ImportProfileStore.install(yaml: updated, into: ctx)
        #expect(p.version == "3.0")
        #expect(try ctx.fetch(FetchDescriptor<ImportProfile>()).count == 1)  // no duplicate
    }
}

@MainActor
@Suite(.serialized)
struct SeederBuiltinTests {

    // Retain the container so its `mainContext` stays alive for the test.
    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }
    // Isolated defaults so the seeded-names marker doesn't touch the shared store.
    let defaults: UserDefaults = UserDefaults(suiteName: "SeederTest-\(UUID().uuidString)")!

    @Test func seedsAllBundledBuiltins() throws {
        Seeder.seedIfNeeded(ctx, defaults: defaults)
        let names = Set(try ctx.fetch(FetchDescriptor<ImportProfile>()).map(\.name))
        #expect(names.contains("Swisscard"))
        #expect(names.contains("Revolut"))
    }

    @Test func deletedBuiltinDoesNotReappear() throws {
        Seeder.seedIfNeeded(ctx, defaults: defaults)
        let revolut = try ctx.fetch(FetchDescriptor<ImportProfile>()).first { $0.name == "Revolut" }
        #expect(revolut != nil)
        ctx.delete(revolut!)
        try ctx.save()

        // Re-seeding must not resurrect a built-in the user removed.
        Seeder.seedIfNeeded(ctx, defaults: defaults)
        let after = try ctx.fetch(FetchDescriptor<ImportProfile>()).filter { $0.name == "Revolut" }
        #expect(after.isEmpty)
    }
}

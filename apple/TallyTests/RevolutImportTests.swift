import Testing
import Foundation
import SwiftData
import ImportKit

/// Reproduces the end-to-end Revolut import (preview → commit → query) to make
/// sure committed rows actually land under the chosen account.
@MainActor
@Suite(.serialized)
struct RevolutImportTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    // Standard Revolut export columns:
    // Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
    private let revolutCSV = """
    Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
    CARD_PAYMENT,Current,2024-01-15 08:23:11,2024-01-15 10:00:00,Coffee Shop,-4.50,0.00,CHF,COMPLETED,100.00
    TOPUP,Current,2024-01-16 09:00:00,2024-01-16 09:05:00,Apple Pay Top-Up,50.00,0.00,CHF,COMPLETED,150.00
    CARD_PAYMENT,Current,2024-01-17 12:00:00,,Pending Store,-9.99,0.00,CHF,PENDING,140.01
    """

    private func revolutAccount() throws -> Account {
        let yaml = StatementImporter.bundledSpecYAMLs()
            .first { (try? ImportSpec(yaml: $0).name) == "Revolut" }
        let profile = ImportProfile(name: "Revolut", specYAML: try #require(yaml))
        let account = Account(name: "Revolut CHF", institution: "Revolut", currencyCode: "CHF")
        account.importProfile = profile
        ctx.insert(profile)
        ctx.insert(account)
        return account
    }

    @Test func previewParsesRevolutRows() throws {
        let account = try revolutAccount()
        let rows = try ImportService.preview(csvText: revolutCSV,
                                             profileYAML: account.importProfile!.specYAML)
        #expect(rows.count == 3)
        #expect(rows[0].description == "Coffee Shop")
        #expect(rows[2].date != Date.distantPast)  // pending row falls back to Started Date
    }

    @Test func commitPersistsRowsUnderAccount() throws {
        let account = try revolutAccount()
        let rows = try ImportService.preview(csvText: revolutCSV,
                                             profileYAML: account.importProfile!.specYAML)

        let batch = try ImportService.commit(rows: rows, to: account, fileName: "revolut.csv", in: ctx)
        #expect(batch.rowCount == 3)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.account?.id == account.id })
        #expect(all.allSatisfy { $0.status == .pending })
    }
}

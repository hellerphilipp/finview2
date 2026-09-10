import Testing
import Foundation
import SwiftData
import ImportKit

@MainActor
@Suite(.serialized)
struct ImportServiceTests {

    let container: ModelContainer = Persistence.makeContainer(inMemory: true)
    var ctx: ModelContext { container.mainContext }

    private let sampleCSV = """
    Date,Merchant,Description,Col3,AccCurrency,AccAmount,OrigCurrency,OrigAmount
    15.01.2025,COOP Store,COOP Zurich,,CHF,42.50,CHF,42.50
    16.01.2025,Migros,Migros Bahnhof,,CHF,23.90,,
    17.01.2025,Amazon,Amazon.de,,CHF,50.00,EUR,45.00
    """

    private func swisscardAccount() throws -> Account {
        let yaml = try StatementImporter.swisscardSpecYAML()
        let profile = ImportProfile(name: "Swisscard", specYAML: yaml)
        let account = Account(name: "Swisscard Credit", institution: "Swisscard", currencyCode: "CHF")
        account.importProfile = profile
        ctx.insert(profile)
        ctx.insert(account)
        return account
    }

    @Test func previewParsesRows() throws {
        let yaml = try StatementImporter.swisscardSpecYAML()
        let rows = try ImportService.preview(csvText: sampleCSV, profileYAML: yaml)
        #expect(rows.count == 3)
        #expect(rows[0].description == "COOP Zurich (COOP Store)")
        #expect(rows[2].originalCurrency == "EUR")
    }

    @Test func commitCreatesPendingTransactionsAndBatch() throws {
        let account = try swisscardAccount()
        let rows = try ImportService.preview(csvText: sampleCSV, profileYAML: account.importProfile!.specYAML)

        let batch = try ImportService.commit(rows: rows, to: account, fileName: "jan.csv", in: ctx)
        #expect(batch.rowCount == 3)

        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(txs.count == 3)
        #expect(txs.allSatisfy { $0.status == .pending })
        #expect(txs.allSatisfy { $0.sourceFile == "jan.csv" })
        #expect(account.txs.count == 3)
    }

    @Test func reimportIsDeduplicated() throws {
        let account = try swisscardAccount()
        let rows = try ImportService.preview(csvText: sampleCSV, profileYAML: account.importProfile!.specYAML)

        _ = try ImportService.commit(rows: rows, to: account, fileName: "jan.csv", in: ctx)
        let secondBatch = try ImportService.commit(rows: rows, to: account, fileName: "jan-again.csv", in: ctx)

        #expect(secondBatch.rowCount == 0)                       // all duplicates
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 3)

        let classification = ImportService.classify(rows: rows, account: account, in: ctx)
        #expect(classification.newCount == 0)
        #expect(classification.duplicateCount == 3)
    }
}

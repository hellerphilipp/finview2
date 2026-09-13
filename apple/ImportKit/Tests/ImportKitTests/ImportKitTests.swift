import Testing
import Foundation
@testable import ImportKit

// MARK: - Helpers

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d
    c.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: {
        var cc = c; cc.timeZone = TimeZone(identifier: "UTC"); return cc
    }()) ?? StatementImporter.parseDate(String(format: "%04d-%02d-%02d", y, m, d))!
}

private func swisscardImporter() throws -> StatementImporter {
    try StatementImporter(yaml: StatementImporter.swisscardSpecYAML())
}

// MARK: - Module

@Test func moduleLoads() {
    #expect(ImportKit.version == "0.1.0")
}

// MARK: - CEL evaluator unit tests

@Test func celStringConcat() throws {
    let v = try evaluateCEL("'a' + '-' + 'b'", variables: [:])
    #expect(v == .string("a-b"))
}

@Test func celTernaryAndComparison() throws {
    let vars: [String: CELValue] = ["row": .list([.string(""), .string("x")])]
    #expect(try evaluateCEL("row[0] != '' ? row[0] : row[1]", variables: vars) == .string("x"))
}

@Test func celSplitAndIndex() throws {
    let v = try evaluateCEL("split('15.01.2025', '.')[2]", variables: [:])
    #expect(v == .string("2025"))
}

@Test func celDoubleAndSignFlip() throws {
    let v = try evaluateCEL("double('42.50') * -1.0", variables: [:])
    #expect(v == .double(-42.5))
}

@Test func celDoubleHandlesCommaAndBlank() throws {
    #expect(try evaluateCEL("double('1,5')", variables: [:]) == .double(1.5))
    #expect(try evaluateCEL("double('')", variables: [:]) == .double(0.0))
}

// MARK: - Swisscard spec parsing

@Test func specDecodesFromYAML() throws {
    let spec = try ImportSpec(yaml: StatementImporter.swisscardSpecYAML())
    #expect(spec.name == "Swisscard")
    #expect(spec.parser.delimiter == ",")
    #expect(spec.parser.skipRows == 1)
    #expect(spec.mappings.amountInAccountCurrency.contains("row[5]"))
}

// MARK: - Oracle tests: outputs must match the Python `statement-importer`

@Test func swisscard_domesticRow() throws {
    let importer = try swisscardImporter()
    let row = ["15.01.2025", "COOP Store", "COOP Zurich", "", "CHF", "42.50", "CHF", "42.50"]
    let n = try importer.normalize(row: row)
    #expect(n.date == date(2025, 1, 15))
    #expect(n.description == "COOP Zurich (COOP Store)")
    #expect(n.amount == Decimal(string: "-42.5"))
    #expect(n.originalAmount == Decimal(string: "-42.5"))
    #expect(n.originalCurrency == "CHF")
}

@Test func swisscard_emptyDescriptionFallsBackToMerchant() throws {
    let importer = try swisscardImporter()
    // test_services.py: 16.01.2025,Merchant B,,,CHF,20.00,,
    let row = ["16.01.2025", "Merchant B", "", "", "CHF", "20.00", "", ""]
    let n = try importer.normalize(row: row)
    #expect(n.description == "Merchant B")
    #expect(n.amount == Decimal(string: "-20"))
    #expect(n.originalAmount == Decimal(string: "-20"))   // falls back to row[5]
    #expect(n.originalCurrency == "CHF")                  // falls back to row[4]
}

@Test func swisscard_foreignCurrencyRow() throws {
    let importer = try swisscardImporter()
    // test_importers.py: 10.03.2025,Amazon,Amazon.de,,CHF,50.00,EUR,45.00
    let row = ["10.03.2025", "Amazon", "Amazon.de", "", "CHF", "50.00", "EUR", "45.00"]
    let n = try importer.normalize(row: row)
    #expect(n.date == date(2025, 3, 10))
    #expect(n.description == "Amazon.de (Amazon)")
    #expect(n.amount == Decimal(string: "-50"))
    #expect(n.originalAmount == Decimal(string: "-45"))
    #expect(n.originalCurrency == "EUR")
}

// MARK: - Full CSV import

@Test func swisscard_parsesFullCSVAndSkipsHeader() throws {
    let importer = try swisscardImporter()
    let csv = """
    Date,Merchant,Description,Col3,AccCurrency,AccAmount,OrigCurrency,OrigAmount
    15.01.2025,COOP Store,COOP Zurich,,CHF,42.50,CHF,42.50
    16.01.2025,Migros,Migros Bahnhof,,CHF,23.90,,

    17.01.2025,Amazon,Amazon.de,,CHF,50.00,EUR,45.00
    """
    let rows = try importer.normalizedRows(fromCSV: csv)
    #expect(rows.count == 3)  // header skipped, blank line skipped
    #expect(rows[0].description == "COOP Zurich (COOP Store)")
    #expect(rows[1].amount == Decimal(string: "-23.9"))
    #expect(rows[2].originalCurrency == "EUR")
}

// MARK: - CSV parser edge cases

@Test func csvHandlesQuotedFieldsWithCommas() {
    let rows = CSV.parse("a,\"b,c\",d\n")
    #expect(rows == [["a", "b,c", "d"]])
}

// MARK: - Bundled specs

@Test func bundledSpecsAreEnumeratedAndParse() throws {
    let yamls = StatementImporter.bundledSpecYAMLs()
    #expect(yamls.count >= 2)  // swisscard + revolut ship today

    let names = try yamls.map { try ImportSpec(yaml: $0).name }
    #expect(names.contains("Swisscard"))
    #expect(names.contains("Revolut"))

    // Every bundled spec must be a valid, compilable importer.
    for yaml in yamls {
        #expect(throws: Never.self) { try StatementImporter(yaml: yaml) }
    }
}

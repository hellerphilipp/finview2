import Foundation

/// One normalized statement line, ready to become a `Transaction`.
/// Field semantics mirror the Python tool exactly (amounts sign-flipped so
/// charges are negative; `amount` is in the account currency).
public struct NormalizedRow: Equatable, Sendable {
    public var date: Date
    public var description: String
    public var amount: Decimal
    public var originalAmount: Decimal
    public var originalCurrency: String

    public init(date: Date, description: String, amount: Decimal,
                originalAmount: Decimal, originalCurrency: String) {
        self.date = date
        self.description = description
        self.amount = amount
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }
}

public struct ImportError: Error, CustomStringConvertible, Equatable {
    public let rowNumber: Int?
    public let field: String?
    public let message: String
    public var description: String {
        var parts = "Import error"
        if let r = rowNumber { parts += " (row \(r))" }
        if let f = field { parts += " [\(f)]" }
        return parts + ": " + message
    }
    init(rowNumber: Int? = nil, field: String? = nil, _ message: String) {
        self.rowNumber = rowNumber
        self.field = field
        self.message = message
    }
}

/// Evaluates an `ImportSpec` against CSV text to produce `NormalizedRow`s.
public struct StatementImporter {
    public let spec: ImportSpec

    // Mapping expressions are compiled once, reused per row.
    private let timestampExpr: CELExpr
    private let descriptionExpr: CELExpr
    private let amountOriginalExpr: CELExpr
    private let currencyOriginalExpr: CELExpr
    private let amountInAccountExpr: CELExpr

    public init(spec: ImportSpec) throws {
        self.spec = spec
        do {
            timestampExpr = try CELParser.parse(spec.mappings.timestamp)
            descriptionExpr = try CELParser.parse(spec.mappings.description)
            amountOriginalExpr = try CELParser.parse(spec.mappings.amountOriginal)
            currencyOriginalExpr = try CELParser.parse(spec.mappings.currencyOriginal)
            amountInAccountExpr = try CELParser.parse(spec.mappings.amountInAccountCurrency)
        } catch let e as CELError {
            throw ImportError("Invalid mapping expression: \(e.message)")
        }
    }

    public init(yaml: String) throws {
        try self.init(spec: try ImportSpec(yaml: yaml))
    }

    /// The bundled Swisscard spec shipped with ImportKit.
    public static func swisscardSpecYAML() throws -> String {
        guard let url = Bundle.module.url(forResource: "swisscard", withExtension: "yaml"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError("Bundled swisscard.yaml not found")
        }
        return text
    }

    /// Parse and normalize an entire CSV document.
    public func normalizedRows(fromCSV text: String) throws -> [NormalizedRow] {
        let delimiter = spec.parser.delimiter.first ?? ","
        let allRows = CSV.parse(text, delimiter: delimiter)
        let dataRows = allRows.dropFirst(spec.parser.skipRows)

        var result: [NormalizedRow] = []
        var rowNumber = spec.parser.skipRows
        for row in dataRows {
            rowNumber += 1
            // Skip fully blank rows, mirroring the Python importer.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            result.append(try normalize(row: row, rowNumber: rowNumber))
        }
        return result
    }

    /// Normalize a single already-split CSV row.
    public func normalize(row: [String], rowNumber: Int? = nil) throws -> NormalizedRow {
        let vars: [String: CELValue] = ["row": .list(row.map { .string($0) })]
        let interp = CELInterpreter(variables: vars)

        func evalString(_ expr: CELExpr, _ field: String) throws -> String {
            let v = try run(expr, field, rowNumber, interp)
            switch v {
            case let .string(s): return s
            case let .double(d): return formatDouble(d)
            case let .bool(b): return String(b)
            case .list: throw ImportError(rowNumber: rowNumber, field: field, "expected string, got list")
            }
        }
        func evalDecimal(_ expr: CELExpr, _ field: String) throws -> Decimal {
            let v = try run(expr, field, rowNumber, interp)
            switch v {
            case let .double(d): return decimal(from: d)
            case let .string(s):
                guard let dec = Decimal(string: s.replacingOccurrences(of: ",", with: ".")) else {
                    throw ImportError(rowNumber: rowNumber, field: field, "cannot parse number '\(s)'")
                }
                return dec
            default:
                throw ImportError(rowNumber: rowNumber, field: field, "expected a number")
            }
        }

        let tsString = try evalString(timestampExpr, "timestamp")
        guard let date = Self.parseDate(tsString) else {
            throw ImportError(rowNumber: rowNumber, field: "timestamp", "cannot parse date '\(tsString)'")
        }

        return NormalizedRow(
            date: date,
            description: try evalString(descriptionExpr, "description"),
            amount: try evalDecimal(amountInAccountExpr, "amount_in_account_currency"),
            originalAmount: try evalDecimal(amountOriginalExpr, "amount_original"),
            originalCurrency: try evalString(currencyOriginalExpr, "currency_original")
        )
    }

    private func run(_ expr: CELExpr, _ field: String, _ rowNumber: Int?, _ interp: CELInterpreter) throws -> CELValue {
        do { return try interp.eval(expr) }
        catch let e as CELError { throw ImportError(rowNumber: rowNumber, field: field, e.message) }
    }

    // Convert a Double to Decimal via its shortest round-trip string, matching
    // Python's `Decimal(str(float))` so values like 19.9 stay exact.
    private func decimal(from d: Double) -> Decimal {
        Decimal(string: formatDouble(d)) ?? Decimal(d)
    }
    private func formatDouble(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    /// Parse an ISO-ish date string (`yyyy-MM-dd` or with time), matching the
    /// Python coercion in `services.py`.
    static func parseDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

/// Minimal RFC-4180-ish CSV parser: handles quoted fields, escaped quotes,
/// and embedded newlines/delimiters.
enum CSV {
    static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        func endField() { record.append(field); field = "" }
        func endRecord() { endField(); rows.append(record); record = [] }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false; i += 1; continue
                }
                field.append(c); i += 1
            } else {
                switch c {
                case "\"": inQuotes = true; i += 1
                case delimiter: endField(); i += 1
                case "\r":
                    if i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    endRecord(); i += 1
                case "\n": endRecord(); i += 1
                default: field.append(c); i += 1
                }
            }
        }
        // Flush trailing field/record if the file didn't end with a newline.
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return rows
    }
}

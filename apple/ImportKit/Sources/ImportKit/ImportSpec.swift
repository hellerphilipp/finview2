import Foundation
import Yams

/// A declarative bank-statement import spec — the same YAML shape used by the
/// Python `statement-importer` tool (`version`, `name`, `parser`, `mappings`).
public struct ImportSpec: Codable, Sendable, Equatable {
    public var version: String
    public var name: String
    public var parser: ParserConfig
    public var mappings: FieldMappings

    public init(version: String, name: String, parser: ParserConfig, mappings: FieldMappings) {
        self.version = version
        self.name = name
        self.parser = parser
        self.mappings = mappings
    }

    /// Decode a spec from YAML text.
    public init(yaml: String) throws {
        self = try YAMLDecoder().decode(ImportSpec.self, from: yaml)
    }

    /// Re-encode this spec to YAML text (used when the user edits a profile).
    public func yamlString() throws -> String {
        try YAMLEncoder().encode(self)
    }
}

public struct ParserConfig: Codable, Sendable, Equatable {
    public var delimiter: String
    public var skipRows: Int

    public init(delimiter: String, skipRows: Int) {
        self.delimiter = delimiter
        self.skipRows = skipRows
    }

    enum CodingKeys: String, CodingKey {
        case delimiter
        case skipRows = "skip_rows"
    }
}

public struct FieldMappings: Codable, Sendable, Equatable {
    public var timestamp: String
    public var description: String
    public var amountOriginal: String
    public var currencyOriginal: String
    public var amountInAccountCurrency: String

    public init(timestamp: String, description: String, amountOriginal: String,
                currencyOriginal: String, amountInAccountCurrency: String) {
        self.timestamp = timestamp
        self.description = description
        self.amountOriginal = amountOriginal
        self.currencyOriginal = currencyOriginal
        self.amountInAccountCurrency = amountInAccountCurrency
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case description
        case amountOriginal = "amount_original"
        case currencyOriginal = "currency_original"
        case amountInAccountCurrency = "amount_in_account_currency"
    }
}

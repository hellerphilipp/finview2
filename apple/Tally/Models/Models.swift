import Foundation
import SwiftData

// MARK: - Enums (stored as raw String for CloudKit friendliness)

enum TransactionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending, confirmed, rejected
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case spending, income, transfer
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// The meaning of a linked group of transactions. Both kinds keep their members
/// in one shared category and displayed together; they differ only in intent
/// and how they're validated — the report math is identical (a group nets its
/// signed amounts into its category).
enum LinkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Money moved between the user's own accounts (equal-and-opposite legs).
    case transfer
    /// A charge later refunded/reimbursed (full or partial), possibly cross-account.
    case refund
    var id: String { rawValue }
}

// MARK: - Account

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var institution: String = ""
    var currencyCode: String = "CHF"
    var colorHex: String = "#4C8BF5"
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    /// The account used to post/clear work expenses (line items posted here as
    /// positive amounts should mirror work-tagged card charges).
    var isExpenseAccount: Bool = false

    var importProfile: ImportProfile?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]?

    @Relationship(deleteRule: .cascade, inverse: \ImportBatch.account)
    var importBatches: [ImportBatch]?

    init(name: String = "", institution: String = "", currencyCode: String = "CHF",
         colorHex: String = "#4C8BF5", sortOrder: Int = 0) {
        self.name = name
        self.institution = institution
        self.currencyCode = currencyCode
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var txs: [Transaction] { transactions ?? [] }
}

// MARK: - Transaction

@Model
final class Transaction {
    var id: UUID = UUID()
    var date: Date = Date.now
    var bookingDate: Date?
    var descriptionText: String = ""
    var rawDescription: String = ""
    var amount: Decimal = Decimal.zero              // account currency, charges negative
    var originalAmount: Decimal = Decimal.zero
    var originalCurrency: String = ""
    var balanceAfter: Decimal?                       // for reconciliation when present
    var statusRaw: String = TransactionStatus.pending.rawValue
    var isWorkExpense: Bool = false
    var note: String = ""
    var sourceFile: String = ""
    var importedAt: Date = Date.now
    var fingerprint: String = ""
    /// Shared id linking a group of related transactions (a transfer's two legs,
    /// or a charge with its refund(s)). `originalName` preserves data from the
    /// former `transferGroupID` column across the rename.
    @Attribute(originalName: "transferGroupID") var linkGroupID: UUID?
    /// What kind of link this is (transfer vs refund). Only meaningful when
    /// `linkGroupID != nil`; defaults to `.transfer` so migrated links read right.
    var linkKindRaw: String = LinkKind.transfer.rawValue
    /// A synthetic "Starting balance" entry seeding an account's balance.
    var isOpeningBalance: Bool = false

    var account: Account?
    var category: SpendingCategory?
    var merchant: Merchant?
    var importBatch: ImportBatch?

    @Relationship(inverse: \Tag.transactions)
    var tags: [Tag]?

    init(date: Date = .now, descriptionText: String = "", rawDescription: String = "",
         amount: Decimal = .zero, originalAmount: Decimal = .zero, originalCurrency: String = "",
         status: TransactionStatus = .pending, sourceFile: String = "", fingerprint: String = "") {
        self.date = date
        self.descriptionText = descriptionText
        self.rawDescription = rawDescription
        self.amount = amount
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.statusRaw = status.rawValue
        self.sourceFile = sourceFile
        self.fingerprint = fingerprint
        self.importedAt = .now
    }

    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var linkKind: LinkKind {
        get { LinkKind(rawValue: linkKindRaw) ?? .transfer }
        set { linkKindRaw = newValue.rawValue }
    }

    /// Whether this transaction belongs to a link group (transfer or refund).
    var isLinked: Bool { linkGroupID != nil }

    /// True when the account currency differs from the original statement currency.
    var isForeignCurrency: Bool {
        guard let acc = account else { return false }
        return !originalCurrency.isEmpty && originalCurrency != acc.currencyCode
    }

    // Non-Comparable-optional helpers so SwiftUI `Table` columns can sort.
    var accountName: String { account?.name ?? "" }
    var categorySortKey: String { category?.displayPath ?? "" }
}

// MARK: - SpendingCategory (one level of subcategories via self-relationship)
// Named `SpendingCategory` rather than `Category` to avoid colliding with the
// Objective-C runtime's `Category` type that Foundation imports into scope.

@Model
final class SpendingCategory {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var symbolName: String = "tag"
    var kindRaw: String = CategoryKind.spending.rawValue
    var sortOrder: Int = 0

    var parent: SpendingCategory?

    @Relationship(deleteRule: .nullify, inverse: \SpendingCategory.parent)
    var children: [SpendingCategory]?

    @Relationship(inverse: \Transaction.category)
    var transactions: [Transaction]?

    init(name: String = "", colorHex: String = "#8E8E93", symbolName: String = "tag",
         kind: CategoryKind = .spending, sortOrder: Int = 0, parent: SpendingCategory? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.parent = parent
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .spending }
        set { kindRaw = newValue.rawValue }
    }

    var isSubcategory: Bool { parent != nil }

    /// "Parent › Child" style path for display.
    var displayPath: String {
        if let p = parent { return "\(p.name) › \(name)" }
        return name
    }
}

// MARK: - Merchant (learning source for auto-tagging)

@Model
final class Merchant {
    var id: UUID = UUID()
    var canonicalName: String = ""
    var patterns: [String] = []           // description/location fragments seen for this merchant
    var defaultCategory: SpendingCategory?

    @Relationship(inverse: \Transaction.merchant)
    var transactions: [Transaction]?

    init(canonicalName: String = "", patterns: [String] = [], defaultCategory: SpendingCategory? = nil) {
        self.canonicalName = canonicalName
        self.patterns = patterns
        self.defaultCategory = defaultCategory
    }
}

// MARK: - Tag (arbitrary labels; work-expense is a common one)

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var isWorkExpense: Bool = false
    var transactions: [Transaction]?

    init(name: String = "", isWorkExpense: Bool = false) {
        self.name = name
        self.isWorkExpense = isWorkExpense
    }
}

// MARK: - ImportProfile (an editable YAML/CEL bank spec)

@Model
final class ImportProfile {
    var id: UUID = UUID()
    var name: String = ""
    var specYAML: String = ""
    var version: String = "1.0"

    @Relationship(inverse: \Account.importProfile)
    var accounts: [Account]?

    init(name: String = "", specYAML: String = "", version: String = "1.0") {
        self.name = name
        self.specYAML = specYAML
        self.version = version
    }
}

// MARK: - ImportBatch (one import run, for traceability + undo)

@Model
final class ImportBatch {
    var id: UUID = UUID()
    var fileName: String = ""
    var importedAt: Date = Date.now
    var rowCount: Int = 0

    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.importBatch)
    var transactions: [Transaction]?

    init(fileName: String = "", rowCount: Int = 0, account: Account? = nil) {
        self.fileName = fileName
        self.rowCount = rowCount
        self.account = account
        self.importedAt = .now
    }
}

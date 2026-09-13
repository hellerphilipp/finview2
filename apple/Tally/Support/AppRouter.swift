import Foundation
import Observation

/// A destination in the app. `account` targets the Transactions browser scoped
/// to one account; `transactionsAll` is the unscoped browser.
enum NavTarget: Hashable {
    case dashboard
    case transactionsAll
    case account(UUID)
    case recurring
    case reports
    case accounts
    case categories
}

/// Status filter for the Transactions browser.
enum StatusFilter: String, CaseIterable, Identifiable {
    case all, toReview, confirmed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .toReview: "To Review"
        case .confirmed: "Confirmed"
        }
    }
    func matches(_ tx: Transaction) -> Bool {
        switch self {
        case .all: true
        case .toReview: tx.status == .pending
        case .confirmed: tx.status == .confirmed
        }
    }
}

/// Shared navigation state so any view can change the selected sidebar section
/// (e.g. a Dashboard button jumping to Transactions filtered to "To Review").
@Observable
final class AppRouter {
    var selection: NavTarget?
    /// A one-shot status filter for TransactionsView to apply when it appears.
    var requestedStatus: StatusFilter?

    init() {
        switch ProcessInfo.processInfo.environment["TALLY_VIEW"] {
        case "transactions": selection = .transactionsAll
        case "recurring": selection = .recurring
        case "reports": selection = .reports
        case "accounts": selection = .accounts
        case "categories": selection = .categories
        default: selection = .dashboard
        }
    }
}

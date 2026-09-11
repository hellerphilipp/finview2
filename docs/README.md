# Tally — Documentation

Tally is a native macOS (SwiftUI + SwiftData) personal-finance app that imports
bank-statement CSVs, helps you review and categorize transactions, and shows
where your money goes. It reuses the declarative YAML/CEL import specs from the
`statement-importer` Python project, evaluated natively in Swift.

The app lives in [`../apple`](../apple). This folder is a lightweight,
website-ready overview of what the app does.

## Features

| Area | Page |
|------|------|
| Accounts, starting balances, the work-expense account | [accounts.md](accounts.md) |
| Importing statements (CSV + import profiles) | [importing.md](importing.md) |
| Browsing & reviewing transactions (keyboard workflow) | [transactions-and-review.md](transactions-and-review.md) |
| Categories & learning auto-tagging | [categories-and-autotagging.md](categories-and-autotagging.md) |
| Cross-account transfer matching | [transfers.md](transfers.md) |
| Work-expense reconciliation | [work-expenses.md](work-expenses.md) |
| Reports (charts, pivot, work grouping) | [reports.md](reports.md) |
| Recurring transaction detection | [recurring.md](recurring.md) |
| Dashboard, settings & data | [dashboard-settings-data.md](dashboard-settings-data.md) |
| Exporting (.tallydb database, CSV drag-out) | [exporting.md](exporting.md) |

## At a glance

- **Multi-account, multi-currency** ledger with per-account balances.
- **Keyboard-first review**: categorize, tag, confirm without the mouse.
- **Learns** which category a merchant usually gets and pre-suggests it.
- **Matches** transfers between your accounts and flags **work expenses** you
  forgot to claim.
- **Reports** spending by category and month; detects **recurring** charges.
- Local-first; iCloud/CloudKit sync is planned.

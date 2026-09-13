# Dashboard, settings & data

## Dashboard

The home screen shows:

- Stat tiles: number of accounts, pending-review count, last-30-days spend
  (each navigates when clicked).
- **Account cards** with balances and a **stale-import warning** when an account
  hasn't received data for a while.
- A **Work Expenses** section listing charges not yet claimed.
- A last-30-days spending-by-category summary.

## Settings (⌘,)

- **Stale-import threshold** — days before an account is flagged as needing a
  fresh import.
- **Default currency**.
- **Show count for unreviewed items** — toggle the sidebar badges.
- **Show status bar** — show a Finder-style status bar at the bottom of the
  Transactions ledger (off by default).

## Data

- Stored locally with **SwiftData**. The model is designed for **CloudKit**, so
  iCloud sync across Mac/iPad/iPhone can be enabled later (needs an Apple
  Developer team + iCloud entitlement).
- **File → Load / Remove Sample Data** populates or clears clearly-labelled
  "Sample …" accounts for trying the app without touching real data.

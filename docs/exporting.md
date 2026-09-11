# Exporting

## Export a database (File → Export Database…, ⇧⌘E)

Exports **all** accounts and transactions to a portable **SQLite** `.sqlite`
file via a standard save panel. The file is a real local database you can open
with the `sqlite3` CLI, DB Browser for SQLite, or any SQLite tool.

The schema mirrors the `statement-importer` Python project's `accounts` and
`transactions` tables (so the file round-trips with that tool) and adds extra
columns for Tally-specific data — `institution`, `color_hex`,
`is_expense_account`, `category`, `is_work_expense`, `is_opening_balance`,
`transfer_group_id`, `note` — so nothing is lost.

## Drag rows out as CSV

Drag one or more selected rows from the Transactions table to Finder, Numbers,
Mail, or a text editor to get them as CSV — a quick alternative to a full export.

> The app's own store is SQLite too, but its schema is internal to SwiftData; the
> export writes a clean, documented database instead of exposing it.

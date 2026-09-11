# Exporting

## Export a database (File → Export Database…, ⇧⌘E)

Exports **all** accounts and transactions to a portable **`.tallydb`** file via a
standard save panel. A `.tallydb` file is a plain **SQLite** database you can open
with the `sqlite3` CLI, DB Browser for SQLite, or any SQLite tool.

It uses Tally's own schema — two readable tables keyed by the app's UUIDs:

- **accounts**: `id`, `name`, `institution`, `currency`, `color_hex`,
  `is_expense_account`, `import_profile`.
- **transactions**: `id`, `account_id`, `date`, `description`, `amount`,
  `original_amount`, `original_currency`, `status`, `category`, `is_work_expense`,
  `is_opening_balance`, `transfer_group_id`, `source_file`, `imported_at`, `note`.

Because the real UUIDs are preserved, the file can be re-imported later without id
collisions.

## Drag rows out as CSV

Drag one or more selected rows from the Transactions table to Finder, Numbers,
Mail, or a text editor to get them as CSV — a quick alternative to a full export.

> The app's own store is SQLite too, but its schema is internal to SwiftData; the
> export writes a clean, documented database instead of exposing it.

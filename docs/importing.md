# Importing statements

Open the importer from the **＋** menu in the Transactions toolbar → **Import
Statement…**. If an account is selected in the sidebar, it's **pre-selected** in
the importer (so a statement lands in the account you're looking at). You can
change the account in the sheet; the preview re-runs against it.

1. Pick the account (its import profile is applied).
2. Choose a CSV file. Rows are parsed and normalized into a preview table.
3. The preview marks each row **New** or **already imported** (duplicate).
4. Import the new rows — they land as **pending** for review.

**Drag & drop:** you can skip the menu entirely — drag a `.csv` onto the
Transactions ledger and the importer opens with that file loaded and the current
account pre-selected, showing the same preview before anything is saved. With
the status bar enabled it shows a **"Drop file to import transactions"** hint
while you drag over the ledger.

**Import profiles** are declarative YAML specs (the same format as the
`statement-importer` Python project). A profile defines the delimiter, header
rows to skip, and CEL-subset expressions mapping columns to date, description,
amount, and currency. Specs for the banks Tally ships with are pre-installed, and
you can add your own — by dragging in a `.yaml` file, picking one from disk, or
adding one by URL. See [import specs](import-specs.md).

**Dedupe** uses a content fingerprint (account + date + amounts + currency +
description), so re-importing an overlapping statement won't create duplicates.

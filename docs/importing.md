# Importing statements

Open the importer from the **＋** menu in the Transactions toolbar → **Import
Statement…**.

1. Pick the account (its import profile is applied).
2. Choose a CSV file. Rows are parsed and normalized into a preview table.
3. The preview marks each row **New** or **already imported** (duplicate).
4. Import the new rows — they land as **pending** for review.

**Import profiles** are declarative YAML specs (the same format as the
`statement-importer` Python project). A profile defines the delimiter, header
rows to skip, and CEL-subset expressions mapping columns to date, description,
amount, and currency. A **Swisscard** profile ships built in; you can add more.

**Dedupe** uses a content fingerprint (account + date + amounts + currency +
description), so re-importing an overlapping statement won't create duplicates.

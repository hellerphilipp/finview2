# statement-importer

A local-first Python library for loading and standardizing bank statements from CSV files.

Designed as the foundation for a personal finance pipeline: import raw statements → standardize → enrich (tagging, merchant detection, classification — TBD).

## Overview

- **Account management** — define accounts with an associated YAML mapping spec
- **CSV import** — declarative, CEL-based field extraction; no hardcoded bank logic
- **Pending/confirmed/rejected workflow** — every imported transaction lands as `pending`, ready for review or downstream enrichment
- **SQLite storage** — file-based, no server required
- **Clean Python API** — import and use directly; no CLI dependency

## Project Structure

```
src/statement_importer/
├── __init__.py               # Public API
├── models.py                 # Account, Transaction, TransactionStatus
├── db.py                     # init_db(), get_session()
├── queries.py                # DB CRUD
├── services.py               # import_csv(), discover_specs()
└── importers/
    ├── engine.py             # CSVImporter — CEL expression evaluator
    ├── schema.py             # Pydantic validation for YAML specs
    └── specs/
        └── Swisscard/
            └── swisscard.yaml
```

## Web UI

A browser-based interface built with Flask and [Pico.css](https://picocss.com) with three sections:

- **Masterdata** — manage accounts and their CSV mapping specs
- **Import** — upload CSV files, assign each to an account, import
- **Process** — view all pending transactions (stub)

### Quickstart

```bash
just run
```

This creates a local `.venv`, installs dependencies, runs migrations, and starts the dev server at <http://localhost:5000>.

Individual recipes:

```bash
just install   # create .venv and install deps
just migrate   # run alembic upgrade head
just run       # start the Flask dev server
just test      # run the test suite
```

The DB defaults to `statement_importer.db` in the project root. Override with `STATEMENT_IMPORTER_DB=/path/to/file.db just run`.

## Setup (library use)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Database

Migrations are managed with Alembic. The DB URL defaults to `sqlite:///statement_importer.db` and can be overridden via the `STATEMENT_IMPORTER_DB_URL` environment variable.

```bash
# Apply migrations to a new database
alembic upgrade head

# After changing models, generate a new migration
alembic revision --autogenerate -m "describe the change"
alembic upgrade head
```

## Usage

```python
import statement_importer as si

# Initialise (file-based SQLite)
si.init_db("myfinances.db")
session = si.get_session()

# Create an account linked to a mapping spec
acc = si.create_account(session, "Swisscard Visa", "CHF", "Swisscard/swisscard.yaml")

# Discover available mapping specs
specs = si.discover_specs()
# [("No Mapping / Manual", None), ("Swisscard", "Swisscard/swisscard.yaml"), ...]

# Import a CSV — transactions land as `pending` immediately
txs = si.import_csv(session, "~/Downloads/export.csv", acc)

# Review and confirm/reject
si.confirm_transactions(session, [tx.id for tx in txs])
# or
si.reject_transactions(session, [tx.id for tx in txs if tx.amount == 0])

# Query
pending = si.get_transactions(session, account_id=acc.id, status=si.TransactionStatus.pending)
```

## Adding a Bank Mapping Spec

Create a subdirectory under `src/statement_importer/importers/specs/` and add a YAML file:

```yaml
version: "1.0"
name: MyBank

parser:
  delimiter: ";"
  skip_rows: 1

mappings:
  timestamp: "row[0]"
  description: "row[1]"
  amount_original: "double(row[2])"
  currency_original: "row[3]"
  amount_in_account_currency: "double(row[2])"
```

Field expressions are evaluated using [CEL (Common Expression Language)](https://cel.dev). Two helper functions are available in all expressions:

- `double(val)` — parse a string to float, handling comma decimals and empty strings
- `split(s, delimiter)` — split a string, returning a list

## Transaction Lifecycle

```
import_csv()
     │
     ▼
  pending  ──── confirm_transactions() ──▶  confirmed
     │
     └────────── reject_transactions() ──▶  rejected
```

Future enrichment steps (tagging, merchant detection, classification) operate on `pending` transactions as a processing queue.

## Testing

```bash
python -m pytest tests/ -v
```

Tests use an in-memory SQLite database (`Base.metadata.create_all()`) without Alembic to stay fast and self-contained.

## License

GPL v3 — see <https://www.gnu.org/licenses/>.

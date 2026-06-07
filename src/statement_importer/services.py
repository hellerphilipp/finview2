# statement-importer — bank statement loading and standardization
# Copyright (C) 2026 Philipp Heller
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import csv
import os
from datetime import datetime
from decimal import Decimal

import yaml
from pydantic import ValidationError
from sqlalchemy.orm import Session

from .importers.engine import CSVImporter
from .importers.schema import ImporterMapping
from .models import Account, Transaction, TransactionStatus

# Default specs directory: package-relative, so it works when installed
_DEFAULT_SPECS_DIR = os.path.join(os.path.dirname(__file__), "importers", "specs")


def discover_specs(
    specs_dir: str | None = None,
) -> list[tuple[str, str | None]]:
    """Scan *specs_dir* for valid YAML mapping specs.

    Returns a list of ``(display_name, relative_path)`` tuples.  The first
    entry is always ``("No Mapping / Manual", None)``.  *relative_path* is
    relative to *specs_dir* (e.g. ``"Swisscard/swisscard.yaml"``).
    """
    if specs_dir is None:
        specs_dir = _DEFAULT_SPECS_DIR

    results: list[tuple[str, str | None]] = [("No Mapping / Manual", None)]

    if not os.path.isdir(specs_dir):
        return results

    for bank_dir in sorted(os.scandir(specs_dir), key=lambda e: e.name):
        if not bank_dir.is_dir():
            continue
        for spec_file in sorted(os.scandir(bank_dir.path), key=lambda e: e.name):
            if not spec_file.name.endswith(".yaml"):
                continue
            try:
                with open(spec_file.path, encoding="utf-8") as f:
                    raw = yaml.safe_load(f)
                config = ImporterMapping(**raw)
                rel_path = os.path.join(bank_dir.name, spec_file.name)
                results.append((config.name, rel_path))
            except (ValidationError, Exception):
                pass

    return results


def import_csv(
    session: Session,
    csv_path: str,
    account: Account,
    source_file: str | None = None,
    specs_dir: str | None = None,
) -> list[Transaction]:
    """Parse *csv_path* using the account's mapping spec and persist the rows.

    All imported transactions are written immediately with
    ``status=pending``.  Returns the list of newly created
    :class:`Transaction` objects.

    Args:
        session:     SQLAlchemy session.
        csv_path:    Path to the CSV file to import.
        account:     Account to associate transactions with.
        source_file: Override the ``source_file`` field (defaults to the
                     CSV filename).
        specs_dir:   Override the specs root directory.

    Raises:
        FileNotFoundError: If *csv_path* does not exist.
        ValueError: If the account has no mapping spec configured.
    """
    if specs_dir is None:
        specs_dir = _DEFAULT_SPECS_DIR

    csv_path = os.path.expanduser(csv_path)
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"File not found: {csv_path}")

    if not account.mapping_spec:
        raise ValueError(
            f"Account '{account.name}' has no mapping spec configured."
        )

    spec_path = os.path.join(specs_dir, account.mapping_spec)
    importer = CSVImporter(spec_path)

    now = datetime.now()
    sf = source_file or os.path.basename(csv_path)
    new_txs: list[Transaction] = []

    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter=importer.config.parser.delimiter)

        for _ in range(importer.config.parser.skip_rows):
            next(reader)

        for row in reader:
            if not row or all(not cell.strip() for cell in row):
                continue

            data = importer.parse_row(row)

            ts = data["timestamp"]
            if isinstance(ts, str):
                try:
                    ts = datetime.fromisoformat(ts.replace(" ", "T"))
                except ValueError:
                    ts = datetime.strptime(ts, "%Y-%m-%d")

            tx = Transaction(
                account_id=account.id,
                timestamp=ts,
                description=str(data["description"]),
                amount=Decimal(str(data["amount_in_account_currency"])),
                original_amount=Decimal(str(data["amount_original"])),
                original_currency=str(data["currency_original"]),
                status=TransactionStatus.pending.value,
                imported_at=now,
                source_file=sf,
            )
            new_txs.append(tx)

    session.add_all(new_txs)
    session.commit()
    return new_txs

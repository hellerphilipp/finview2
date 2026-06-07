"""Tests for the public API surface (statement_importer.__init__)."""

import os
from datetime import datetime
from decimal import Decimal

import pytest

import statement_importer as si
from statement_importer.models import TransactionStatus

SPECS_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "src",
    "statement_importer",
    "importers",
    "specs",
)

SWISSCARD_HEADER = "Date,Merchant,Description,Col3,AccCurrency,AccAmount,OrigCurrency,OrigAmount"
SWISSCARD_ROW = "15.01.2025,COOP Store,COOP Zurich,,CHF,42.50,CHF,42.50"


def _write_csv(tmp_path, rows):
    path = os.path.join(tmp_path, "stmt.csv")
    with open(path, "w") as f:
        f.write("\n".join(rows) + "\n")
    return path


class TestAccountCRUD:
    def test_create_and_get(self, session):
        acc = si.create_account(session, "My Bank", "CHF", "Swisscard/swisscard.yaml")
        assert acc.id is not None

        fetched = si.get_account(session, acc.id)
        assert fetched.name == "My Bank"

    def test_get_all_accounts(self, session):
        si.create_account(session, "A", "CHF")
        si.create_account(session, "B", "EUR")
        accounts = si.get_all_accounts(session)
        assert len(accounts) == 2

    def test_update_account(self, session):
        acc = si.create_account(session, "Old Name", "CHF")
        updated = si.update_account(session, acc.id, name="New Name")
        assert updated.name == "New Name"

    def test_get_nonexistent_account_returns_none(self, session):
        assert si.get_account(session, 9999) is None

    def test_update_nonexistent_account_raises(self, session):
        with pytest.raises(ValueError):
            si.update_account(session, 9999, name="Ghost")


class TestImportAndLifecycle:
    def test_full_pipeline(self, session, tmp_path):
        acc = si.create_account(session, "Visa", "CHF", "Swisscard/swisscard.yaml")
        path = _write_csv(tmp_path, [SWISSCARD_HEADER, SWISSCARD_ROW])

        txs = si.import_csv(session, path, acc, specs_dir=SPECS_DIR)
        assert len(txs) == 1
        assert txs[0].status == TransactionStatus.pending.value

        # Confirm
        count = si.confirm_transactions(session, [txs[0].id])
        assert count == 1

        confirmed = si.get_transactions(session, acc.id, status=TransactionStatus.confirmed)
        assert len(confirmed) == 1
        assert confirmed[0].status == TransactionStatus.confirmed.value

    def test_reject_transactions(self, session, tmp_path):
        acc = si.create_account(session, "Visa2", "CHF", "Swisscard/swisscard.yaml")
        rows = [
            SWISSCARD_HEADER,
            "15.01.2025,A,,,CHF,10.00,,",
            "16.01.2025,B,,,CHF,20.00,,",
        ]
        path = _write_csv(tmp_path, rows)
        txs = si.import_csv(session, path, acc, specs_dir=SPECS_DIR)

        si.reject_transactions(session, [txs[0].id])
        si.confirm_transactions(session, [txs[1].id])

        pending = si.get_transactions(session, acc.id, status=TransactionStatus.pending)
        rejected = si.get_transactions(session, acc.id, status=TransactionStatus.rejected)
        confirmed = si.get_transactions(session, acc.id, status=TransactionStatus.confirmed)

        assert len(pending) == 0
        assert len(rejected) == 1
        assert len(confirmed) == 1

    def test_get_transactions_no_filter(self, session, tmp_path):
        acc = si.create_account(session, "Visa3", "CHF", "Swisscard/swisscard.yaml")
        rows = [SWISSCARD_HEADER, SWISSCARD_ROW, "16.01.2025,B,,,CHF,5.00,,"]
        path = _write_csv(tmp_path, rows)
        si.import_csv(session, path, acc, specs_dir=SPECS_DIR)

        all_txs = si.get_transactions(session, account_id=acc.id)
        assert len(all_txs) == 2

    def test_discover_specs(self):
        specs = si.discover_specs(SPECS_DIR)
        assert specs[0] == ("No Mapping / Manual", None)
        assert any(name == "Swisscard" for name, _ in specs)

    def test_confirm_empty_list(self, session):
        count = si.confirm_transactions(session, [])
        assert count == 0

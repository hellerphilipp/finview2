import csv
import os
import tempfile
from datetime import datetime
from decimal import Decimal

import pytest

from statement_importer.models import Account, TransactionStatus
from statement_importer.services import discover_specs, import_csv

SPECS_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "src",
    "statement_importer",
    "importers",
    "specs",
)

# A minimal valid Swisscard CSV row (header + one data row)
SWISSCARD_HEADER = "Date,Merchant,Description,Col3,AccCurrency,AccAmount,OrigCurrency,OrigAmount"
SWISSCARD_ROW = "15.01.2025,COOP Store,COOP Zurich,,CHF,42.50,CHF,42.50"


def _write_csv(tmp_path, rows: list[str]) -> str:
    path = os.path.join(tmp_path, "test.csv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    return path


class TestDiscoverSpecs:
    def test_returns_no_mapping_first(self):
        specs = discover_specs(SPECS_DIR)
        assert specs[0] == ("No Mapping / Manual", None)

    def test_discovers_swisscard(self):
        specs = discover_specs(SPECS_DIR)
        names = [name for name, _ in specs]
        assert "Swisscard" in names

    def test_swisscard_has_relative_path(self):
        specs = discover_specs(SPECS_DIR)
        paths = {name: path for name, path in specs}
        assert "Swisscard" in paths
        assert paths["Swisscard"].endswith("swisscard.yaml")

    def test_nonexistent_dir_returns_only_manual(self):
        specs = discover_specs("/nonexistent/path/to/specs")
        assert specs == [("No Mapping / Manual", None)]


class TestImportCsv:
    def test_imports_transactions(self, session, sample_account, tmp_path):
        path = _write_csv(tmp_path, [SWISSCARD_HEADER, SWISSCARD_ROW])
        txs = import_csv(session, path, sample_account, specs_dir=SPECS_DIR)

        assert len(txs) == 1
        tx = txs[0]
        assert tx.status == TransactionStatus.pending.value
        assert tx.account_id == sample_account.id
        assert tx.description != ""
        assert tx.amount == Decimal("-42.50")
        assert tx.original_currency == "CHF"
        assert tx.source_file == "test.csv"

    def test_imports_multiple_rows(self, session, sample_account, tmp_path):
        rows = [
            SWISSCARD_HEADER,
            "15.01.2025,Merchant A,Desc A,,CHF,10.00,CHF,10.00",
            "16.01.2025,Merchant B,,,CHF,20.00,,",
            "17.01.2025,Merchant C,,,CHF,30.00,,",
        ]
        path = _write_csv(tmp_path, rows)
        txs = import_csv(session, path, sample_account, specs_dir=SPECS_DIR)
        assert len(txs) == 3

    def test_skips_blank_rows(self, session, sample_account, tmp_path):
        path = _write_csv(tmp_path, [SWISSCARD_HEADER, SWISSCARD_ROW, "", "   "])
        txs = import_csv(session, path, sample_account, specs_dir=SPECS_DIR)
        assert len(txs) == 1

    def test_source_file_override(self, session, sample_account, tmp_path):
        path = _write_csv(tmp_path, [SWISSCARD_HEADER, SWISSCARD_ROW])
        txs = import_csv(
            session, path, sample_account, source_file="my_export.csv", specs_dir=SPECS_DIR
        )
        assert txs[0].source_file == "my_export.csv"

    def test_file_not_found(self, session, sample_account):
        with pytest.raises(FileNotFoundError):
            import_csv(session, "/nonexistent/file.csv", sample_account, specs_dir=SPECS_DIR)

    def test_no_mapping_spec_raises(self, session, account_no_spec, tmp_path):
        path = _write_csv(tmp_path, [SWISSCARD_HEADER, SWISSCARD_ROW])
        with pytest.raises(ValueError, match="no mapping spec"):
            import_csv(session, path, account_no_spec, specs_dir=SPECS_DIR)

    def test_all_pending_after_import(self, session, sample_account, tmp_path):
        rows = [SWISSCARD_HEADER] + [
            f"0{i}.01.2025,Shop {i},,,CHF,{i}.00,," for i in range(1, 5)
        ]
        path = _write_csv(tmp_path, rows)
        txs = import_csv(session, path, sample_account, specs_dir=SPECS_DIR)
        assert all(tx.status == TransactionStatus.pending.value for tx in txs)

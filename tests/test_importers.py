import os
import pytest
from pydantic import ValidationError

from statement_importer.importers.schema import DataMapping, ImporterMapping, ParserConfig
from statement_importer.importers.engine import CSVImporter

SWISSCARD_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "src",
    "statement_importer",
    "importers",
    "specs",
    "Swisscard",
    "swisscard.yaml",
)


class TestImporterSchema:
    def test_valid_swisscard_yaml(self):
        importer = CSVImporter(SWISSCARD_PATH)
        assert importer.config.name == "Swisscard"
        assert importer.config.version == "1.0"
        assert importer.config.parser.delimiter == ","
        assert importer.config.parser.skip_rows == 1

    def test_invalid_schema_missing_fields(self):
        with pytest.raises(ValidationError):
            ImporterMapping(version="1.0", name="Bad")

    def test_invalid_schema_missing_mapping_fields(self):
        with pytest.raises(ValidationError):
            ImporterMapping(
                version="1.0",
                name="Bad",
                parser=ParserConfig(delimiter=",", skip_rows=0),
                mappings=DataMapping(timestamp="row[0]"),  # missing other fields
            )

    def test_invalid_yaml_path(self):
        with pytest.raises(FileNotFoundError):
            CSVImporter("/nonexistent/path.yaml")


class TestCSVImporterParseRow:
    @pytest.fixture()
    def importer(self):
        return CSVImporter(SWISSCARD_PATH)

    def test_parse_swisscard_row_full(self, importer):
        row = [
            "15.01.2025",   # row[0] date
            "COOP Store",   # row[1] merchant
            "COOP Zurich",  # row[2] extra description
            "",             # row[3]
            "CHF",          # row[4] account currency
            "42.50",        # row[5] amount in account currency
            "CHF",          # row[6] original currency
            "42.50",        # row[7] original amount
        ]
        result = importer.parse_row(row)

        assert result["timestamp"] == "2025-01-15"
        assert "COOP Zurich" in result["description"]
        assert "COOP Store" in result["description"]
        assert result["amount_original"] == -42.50
        assert result["currency_original"] == "CHF"
        assert result["amount_in_account_currency"] == -42.50

    def test_parse_row_no_extra_description(self, importer):
        row = ["20.02.2025", "SBB Ticket", "", "", "CHF", "15.00", "", ""]
        result = importer.parse_row(row)

        assert result["timestamp"] == "2025-02-20"
        assert result["description"] == "SBB Ticket"
        assert result["amount_in_account_currency"] == -15.00
        assert result["currency_original"] == "CHF"

    def test_parse_row_foreign_currency(self, importer):
        row = ["10.03.2025", "Amazon", "Amazon.de", "", "CHF", "50.00", "EUR", "45.00"]
        result = importer.parse_row(row)

        assert result["currency_original"] == "EUR"
        assert result["amount_original"] == -45.00
        assert result["amount_in_account_currency"] == -50.00

    def test_empty_amount_fields(self, importer):
        row = ["01.03.2025", "Test", "", "", "CHF", "", "", ""]
        result = importer.parse_row(row)
        assert result["amount_original"] == 0.0
        assert result["amount_in_account_currency"] == 0.0

from datetime import datetime
from decimal import Decimal

from statement_importer.models import Account, Transaction, TransactionStatus


class TestAccount:
    def test_create_account(self, session):
        acc = Account(name="Checking", currency="CHF")
        session.add(acc)
        session.commit()

        reloaded = session.get(Account, acc.id)
        assert reloaded.name == "Checking"
        assert reloaded.currency == "CHF"
        assert reloaded.mapping_spec is None

    def test_account_name_unique(self, session):
        session.add(Account(name="Savings", currency="EUR"))
        session.commit()

        from sqlalchemy.exc import IntegrityError
        session.add(Account(name="Savings", currency="USD"))
        with pytest.raises(IntegrityError):
            session.commit()

    def test_account_repr(self, session):
        acc = Account(name="Test", currency="USD")
        session.add(acc)
        session.commit()
        assert "Test" in repr(acc)


import pytest


class TestTransaction:
    def test_create_transaction(self, session, sample_account):
        tx = Transaction(
            account_id=sample_account.id,
            timestamp=datetime(2025, 3, 1),
            description="Coffee",
            amount=Decimal("-4.50"),
            original_amount=Decimal("-4.50"),
            original_currency="CHF",
            status=TransactionStatus.pending.value,
            imported_at=datetime.now(),
        )
        session.add(tx)
        session.commit()

        reloaded = session.get(Transaction, tx.id)
        assert reloaded.description == "Coffee"
        assert reloaded.status == TransactionStatus.pending.value
        assert reloaded.source_file is None

    def test_transaction_default_status_is_pending(self, session, sample_account):
        tx = Transaction(
            account_id=sample_account.id,
            timestamp=datetime(2025, 3, 1),
            description="Test",
            amount=Decimal("10.00"),
            original_amount=Decimal("10.00"),
            original_currency="CHF",
            status=TransactionStatus.pending.value,
            imported_at=datetime.now(),
        )
        session.add(tx)
        session.commit()
        assert tx.status == "pending"

    def test_transaction_repr(self, session, sample_account):
        tx = Transaction(
            account_id=sample_account.id,
            timestamp=datetime(2025, 3, 1),
            description="Test",
            amount=Decimal("-10.00"),
            original_amount=Decimal("-10.00"),
            original_currency="CHF",
            status=TransactionStatus.pending.value,
            imported_at=datetime.now(),
        )
        session.add(tx)
        session.commit()
        assert "pending" in repr(tx)

    def test_cascade_delete(self, session, sample_account):
        tx = Transaction(
            account_id=sample_account.id,
            timestamp=datetime(2025, 3, 1),
            description="To delete",
            amount=Decimal("-1.00"),
            original_amount=Decimal("-1.00"),
            original_currency="CHF",
            status=TransactionStatus.pending.value,
            imported_at=datetime.now(),
        )
        session.add(tx)
        session.commit()
        tx_id = tx.id

        session.delete(sample_account)
        session.commit()

        assert session.get(Transaction, tx_id) is None

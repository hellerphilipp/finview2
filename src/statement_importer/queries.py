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

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from .models import Account, Transaction, TransactionStatus

_UNSET = object()


# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------


def create_account(
    session: Session,
    name: str,
    currency: str,
    mapping_spec: str | None = None,
) -> Account:
    """Create and persist a new account."""
    account = Account(name=name, currency=currency, mapping_spec=mapping_spec)
    session.add(account)
    session.commit()
    return account


def get_all_accounts(session: Session) -> list[Account]:
    return list(session.execute(select(Account)).scalars().all())


def get_account(session: Session, account_id: int) -> Account | None:
    return session.get(Account, account_id)


def update_account(
    session: Session,
    account_id: int,
    name: str | None = _UNSET,
    currency: str | None = _UNSET,
    mapping_spec: str | None = _UNSET,
) -> Account:
    """Update fields on an existing account.  Pass only the fields to change."""
    account = session.get(Account, account_id)
    if account is None:
        raise ValueError(f"Account {account_id} not found")
    if name is not _UNSET:
        account.name = name
    if currency is not _UNSET:
        account.currency = currency
    if mapping_spec is not _UNSET:
        account.mapping_spec = mapping_spec
    session.commit()
    return account


# ---------------------------------------------------------------------------
# Transactions
# ---------------------------------------------------------------------------


def get_transactions(
    session: Session,
    account_id: int | None = None,
    status: TransactionStatus | str | None = None,
) -> list[Transaction]:
    """Return transactions, optionally filtered by account and/or status."""
    stmt = select(Transaction)
    if account_id is not None:
        stmt = stmt.where(Transaction.account_id == account_id)
    if status is not None:
        status_val = status.value if isinstance(status, TransactionStatus) else status
        stmt = stmt.where(Transaction.status == status_val)
    stmt = stmt.order_by(Transaction.timestamp)
    return list(session.execute(stmt).scalars().all())


def _set_transaction_status(
    session: Session, transaction_ids: list[int], status: TransactionStatus
) -> int:
    if not transaction_ids:
        return 0
    stmt = (
        update(Transaction)
        .where(Transaction.id.in_(transaction_ids))
        .values(status=status.value)
    )
    result = session.execute(stmt)
    session.commit()
    return result.rowcount


def confirm_transactions(session: Session, transaction_ids: list[int]) -> int:
    """Mark the given transactions as confirmed.  Returns the count updated."""
    return _set_transaction_status(session, transaction_ids, TransactionStatus.confirmed)


def reject_transactions(session: Session, transaction_ids: list[int]) -> int:
    """Mark the given transactions as rejected.  Returns the count updated."""
    return _set_transaction_status(session, transaction_ids, TransactionStatus.rejected)

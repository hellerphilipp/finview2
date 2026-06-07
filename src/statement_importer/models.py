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

import enum
from datetime import datetime
from decimal import Decimal
from typing import List, Optional

from sqlalchemy import DateTime, ForeignKey, MetaData, Numeric, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

convention = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=convention)


class TransactionStatus(str, enum.Enum):
    pending = "pending"
    confirmed = "confirmed"
    rejected = "rejected"


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True)
    # Plain string — no enum constraint so new currencies don't require a migration
    currency: Mapped[str] = mapped_column(String(10))
    # Relative path within the specs/ directory, e.g. "Swisscard/swisscard.yaml"
    mapping_spec: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    transactions: Mapped[List["Transaction"]] = relationship(
        back_populates="account", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Account id={self.id} name={self.name!r} currency={self.currency}>"


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"))

    timestamp: Mapped[datetime] = mapped_column(DateTime)
    description: Mapped[str] = mapped_column(String(500))

    # Amount in the account's own currency (after FX conversion if applicable)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 4))
    # Original amount and currency as they appeared in the statement
    original_amount: Mapped[Decimal] = mapped_column(Numeric(14, 4))
    original_currency: Mapped[str] = mapped_column(String(10))

    # Workflow status: pending → confirmed or rejected
    status: Mapped[str] = mapped_column(
        String(20), default=TransactionStatus.pending.value
    )

    imported_at: Mapped[datetime] = mapped_column(DateTime)
    # Filename of the source CSV, for traceability
    source_file: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    account: Mapped["Account"] = relationship(back_populates="transactions")

    def __repr__(self) -> str:
        return (
            f"<Transaction id={self.id} date={self.timestamp.date()} "
            f"amount={self.amount} status={self.status!r}>"
        )

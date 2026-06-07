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

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

engine = None
SessionLocal = None


def init_db(db_path: str | None = None) -> None:
    """Initialise the database engine and session factory.

    Args:
        db_path: Path to the SQLite file.  Pass ``None`` (or omit) to use an
                 in-memory database — useful for tests.
    """
    global engine, SessionLocal

    if db_path is None:
        engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    else:
        engine = create_engine(
            f"sqlite:///{db_path}",
            connect_args={"check_same_thread": False},
        )

    SessionLocal = sessionmaker(bind=engine)


def get_session():
    """Return a new session.  Caller is responsible for closing it."""
    if SessionLocal is None:
        raise RuntimeError("Database not initialised — call init_db() first.")
    return SessionLocal()

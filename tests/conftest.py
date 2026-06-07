import pytest
from sqlalchemy.pool import StaticPool
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from statement_importer.models import Base, Account, TransactionStatus


@pytest.fixture()
def engine():
    """In-memory SQLite engine shared across all connections in a test."""
    eng = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture()
def session(engine):
    """Fresh session for each test, closed on teardown."""
    Session = sessionmaker(bind=engine)
    s = Session()
    yield s
    s.close()


@pytest.fixture()
def sample_account(session):
    """An account with the Swisscard mapping spec."""
    acc = Account(
        name="Swisscard Visa",
        currency="CHF",
        mapping_spec="Swisscard/swisscard.yaml",
    )
    session.add(acc)
    session.commit()
    return acc


@pytest.fixture()
def account_no_spec(session):
    """An account without a mapping spec."""
    acc = Account(name="Manual Account", currency="USD", mapping_spec=None)
    session.add(acc)
    session.commit()
    return acc

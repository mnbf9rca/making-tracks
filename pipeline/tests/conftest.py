import pathlib

import pytest

from mt_pipeline import store


def pytest_addoption(parser):
    parser.addoption(
        "--live",
        action="store_true",
        default=False,
        help="enable tests that make live provider network calls",
    )


@pytest.fixture
def conn(tmp_path: pathlib.Path):
    c = store.connect(tmp_path / "work.db")
    store.init_schema(c)
    yield c
    c.close()

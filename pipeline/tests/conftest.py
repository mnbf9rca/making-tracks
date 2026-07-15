import pathlib

import pytest

from mt_pipeline import store


@pytest.fixture
def conn(tmp_path: pathlib.Path):
    c = store.connect(tmp_path / "work.db")
    store.init_schema(c)
    yield c
    c.close()

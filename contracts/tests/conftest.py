import pathlib

import pytest


@pytest.fixture(scope="session")
def contracts_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]

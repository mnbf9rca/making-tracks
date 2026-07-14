"""Schema version registry and the §5.6 reader-compatibility policy."""

from __future__ import annotations

import enum
import json
import pathlib

_PACKAGE_VERSIONS_PATH = pathlib.Path(__file__).with_name("versions.json")
_ROOT_VERSIONS_PATH = pathlib.Path(__file__).resolve().parents[2] / "versions.json"


def _load_schema_versions() -> dict[str, int]:
    if _PACKAGE_VERSIONS_PATH.exists():
        return json.loads(_PACKAGE_VERSIONS_PATH.read_text())
    return json.loads(_ROOT_VERSIONS_PATH.read_text())


SCHEMA_VERSIONS: dict[str, int] = _load_schema_versions()


class Compat(enum.Enum):
    OK = "ok"
    TOO_NEW = "too_new"
    TOO_OLD = "too_old"


def check_version(reader_max: int, data_version: int, min_supported: int) -> Compat:
    if data_version > reader_max:
        return Compat.TOO_NEW
    if data_version < min_supported:
        return Compat.TOO_OLD
    return Compat.OK

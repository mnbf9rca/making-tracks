import json
import tomllib

from mt_contracts.versions import (
    MIN_SUPPORTED_VERSIONS,
    SCHEMA_VERSIONS,
    Compat,
    check_version,
)
from mt_contracts import versions


REQUIRED_KEYS = {
    "place",
    "tile",
    "manifest",
    "region_config",
    "registry_record",
    "id_scheme",
}


def test_versions_json_matches_module(contracts_root):
    on_disk = json.loads((contracts_root / "versions.json").read_text())
    assert on_disk == SCHEMA_VERSIONS


def test_versions_json_is_packaged_with_wheel(contracts_root):
    pyproject = tomllib.loads((contracts_root / "pyproject.toml").read_text())
    force_include = pyproject["tool"]["hatch"]["build"]["targets"]["wheel"][
        "force-include"
    ]
    assert force_include["versions.json"] == "src/mt_contracts/versions.json"


def test_versions_loader_accepts_packaged_copy(tmp_path, monkeypatch):
    packaged = tmp_path / "versions.json"
    packaged.write_text(json.dumps(SCHEMA_VERSIONS))
    monkeypatch.setattr(versions, "_PACKAGE_VERSIONS_PATH", packaged)
    monkeypatch.setattr(versions, "_ROOT_VERSIONS_PATH", tmp_path / "missing.json")
    assert versions._load_schema_versions() == SCHEMA_VERSIONS


def test_all_version_keys_present():
    assert REQUIRED_KEYS <= set(SCHEMA_VERSIONS)
    assert all(isinstance(v, int) and v >= 1 for v in SCHEMA_VERSIONS.values())


def test_min_supported_floor_is_documented_for_every_artifact():
    assert set(MIN_SUPPORTED_VERSIONS) == set(SCHEMA_VERSIONS)
    assert all(
        1 <= MIN_SUPPORTED_VERSIONS[key] <= SCHEMA_VERSIONS[key]
        for key in SCHEMA_VERSIONS
    )


def test_check_version_equal_is_ok():
    assert check_version(reader_max=1, data_version=1, min_supported=1) is Compat.OK


def test_check_version_newer_data_is_too_new():
    assert check_version(reader_max=1, data_version=2, min_supported=1) is Compat.TOO_NEW


def test_check_version_older_within_window_is_ok():
    assert check_version(reader_max=3, data_version=2, min_supported=2) is Compat.OK


def test_check_version_older_below_window_is_too_old():
    assert check_version(reader_max=3, data_version=1, min_supported=2) is Compat.TOO_OLD

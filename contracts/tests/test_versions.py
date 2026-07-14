import json

from mt_contracts.versions import SCHEMA_VERSIONS, Compat, check_version


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


def test_all_version_keys_present():
    assert REQUIRED_KEYS <= set(SCHEMA_VERSIONS)
    assert all(isinstance(v, int) and v >= 1 for v in SCHEMA_VERSIONS.values())


def test_check_version_equal_is_ok():
    assert check_version(reader_max=1, data_version=1, min_supported=1) is Compat.OK


def test_check_version_newer_data_is_too_new():
    assert check_version(reader_max=1, data_version=2, min_supported=1) is Compat.TOO_NEW


def test_check_version_older_within_window_is_ok():
    assert check_version(reader_max=3, data_version=2, min_supported=2) is Compat.OK


def test_check_version_older_below_window_is_too_old():
    assert check_version(reader_max=3, data_version=1, min_supported=2) is Compat.TOO_OLD

import json

from mt_contracts.validation import is_valid, validate_instance


def test_uk_config_valid(contracts_root):
    validate_instance(
        "region-config", json.loads((contracts_root / "regions/uk.json").read_text())
    )


def test_malaysia_config_valid(contracts_root):
    validate_instance(
        "region-config",
        json.loads((contracts_root / "regions/malaysia.json").read_text()),
    )


def test_region_id_pattern_rejects_uppercase(contracts_root):
    cfg = json.loads((contracts_root / "regions/uk.json").read_text())
    cfg["region_id"] = "UK"
    assert not is_valid("region-config", cfg)

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


def test_sources_are_additive_not_hard_enumerated(contracts_root):
    cfg = json.loads((contracts_root / "regions/uk.json").read_text())
    cfg["sources"] = {
        "wikidata": True,
        "new_register": {"id": "new_register", "enabled": False},
    }
    validate_instance("region-config", cfg)


def test_region_config_rejects_non_v1_basemap_maxzoom(contracts_root):
    cfg = json.loads((contracts_root / "regions/uk.json").read_text())
    cfg["basemap"]["maxzoom"] = 15
    assert not is_valid("region-config", cfg)


def test_region_config_rejects_pageview_windows_over_props_budget(contracts_root):
    cfg = json.loads((contracts_root / "regions/malaysia.json").read_text())
    cfg["pageviews"]["months"] = 13
    assert not is_valid("region-config", cfg)

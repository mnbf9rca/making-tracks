import json
import pathlib
import re

from mt_contracts.validation import is_valid, validate_instance


def test_united_kingdom_config_valid(contracts_root):
    validate_instance(
        "region-config",
        json.loads((contracts_root / "regions/united-kingdom.json").read_text()),
    )


def test_malaysia_singapore_brunei_config_valid(contracts_root):
    validate_instance(
        "region-config",
        json.loads(
            (contracts_root / "regions/malaysia-singapore-brunei.json").read_text()
        ),
    )


def test_region_ids_match_geofabrik_path_slugs(contracts_root):
    uk = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    msb = json.loads(
        (contracts_root / "regions/malaysia-singapore-brunei.json").read_text()
    )
    assert uk["region_id"] == "united-kingdom"
    assert msb["region_id"] == "malaysia-singapore-brunei"
    assert msb["display_name"] == "Malaysia, Singapore, and Brunei"


def _slug_from_geofabrik_url(url: str) -> str:
    filename = pathlib.PurePosixPath(url).name
    return re.sub(r"-latest\.osm\.pbf$", "", filename)


def test_region_ids_and_display_names_match_geofabrik_source_config(contracts_root):
    acquire = json.loads(
        (contracts_root.parent / "pipeline/config/acquire_sources.json").read_text()
    )
    expected_display_names = {
        "united-kingdom": "United Kingdom",
        "malaysia-singapore-brunei": "Malaysia, Singapore, and Brunei",
    }
    for path in sorted((contracts_root / "regions").glob("*.json")):
        cfg = json.loads(path.read_text())
        region_id = cfg["region_id"]
        assert path.name == f"{region_id}.json"
        assert region_id not in {"uk", "malaysia"}
        assert "_" not in region_id
        assert region_id in acquire["osm"]
        assert _slug_from_geofabrik_url(acquire["osm"][region_id]["url"]) == region_id
        assert cfg["display_name"] == expected_display_names[region_id]


def test_legacy_region_configs_are_not_available(contracts_root):
    for legacy in ("uk", "malaysia"):
        assert not (contracts_root / "regions" / f"{legacy}.json").exists()


def test_region_id_pattern_rejects_uppercase(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["region_id"] = "UK"
    assert not is_valid("region-config", cfg)


def test_sources_are_additive_not_hard_enumerated(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["sources"] = {
        "wikidata": True,
        "new_register": {"id": "new_register", "enabled": False},
    }
    validate_instance("region-config", cfg)


def test_region_config_rejects_hyphenated_source_keys(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["sources"] = {"open-plaques": True}
    assert not is_valid("region-config", cfg)


def test_region_config_rejects_non_v1_basemap_maxzoom(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["basemap"]["maxzoom"] = 15
    assert not is_valid("region-config", cfg)


def test_region_config_rejects_pageview_windows_over_props_budget(contracts_root):
    cfg = json.loads(
        (contracts_root / "regions/malaysia-singapore-brunei.json").read_text()
    )
    cfg["pageviews"]["months"] = 13
    assert not is_valid("region-config", cfg)


def test_region_config_accepts_zone_level_and_prune_list_contract(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["zone_levels"] = {"2": "country", "4": "region", "6": "county"}
    cfg["zone_allowlist"] = ["osm_r100", "wd_q145"]
    validate_instance("region-config", cfg)


def test_region_config_rejects_name_derived_zone_allowlist_ids(contracts_root):
    cfg = json.loads((contracts_root / "regions/united-kingdom.json").read_text())
    cfg["zone_levels"] = {"2": "country"}
    cfg["zone_allowlist"] = ["South East England"]
    assert not is_valid("region-config", cfg)

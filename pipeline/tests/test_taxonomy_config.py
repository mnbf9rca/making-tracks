import json
import pathlib
import re

import mt_contracts
from mt_pipeline import categorize


CONFIG_DIR = pathlib.Path(__file__).parents[1] / "config"
_QID = re.compile(r"Q[0-9]+")
_PRECEDENCE_KINDS = {"wd_p31", "osm_tag", "hehle", "plaque"}


def _load(name):
    return json.loads((CONFIG_DIR / name).read_text())


def test_taxonomy_config_invariants():
    data = _load("taxonomy.json")
    categories = data["categories"]
    uncovered = data["uncovered"]
    maps = (data["class_map"], data["tag_map"], data["source_map"])

    assert 5 <= len(categories) <= 7
    assert uncovered not in categories
    assert set(data["precedence"]) <= _PRECEDENCE_KINDS
    for label in categories + [uncovered]:
        assert isinstance(label, str)
        assert 0 < len(label) <= 64
        assert mt_contracts.strip_unsafe_text(label) == label

    mapped = set()
    for mapping in maps:
        assert isinstance(mapping, dict)
        for category in mapping.values():
            assert category in categories
            mapped.add(category)
    assert set(categories) <= mapped


def test_taxonomy_source_map_matches_source_precedence_entries():
    data = _load("taxonomy.json")
    source_map = data["source_map"]
    for kind in ("hehle", "plaque"):
        assert kind in data["precedence"]
        assert kind in source_map
        assert source_map[kind] in data["categories"]


def test_wikidata_allowlist_is_a3_marked_allow_only_qid_list():
    data = _load("wikidata_class_allowlist.json")

    assert "WP-A3" in data["_header"]
    assert "audit" in data["_header"].lower()
    assert set(data) == {"_header", "allow"}
    assert isinstance(data["allow"], list)
    assert data["allow"] == sorted(set(data["allow"]))
    assert all(_QID.fullmatch(qid) for qid in data["allow"])


def test_load_taxonomy_rejects_missing_rule_maps(tmp_path):
    data = _load("taxonomy.json")
    data.pop("class_map")
    path = tmp_path / "taxonomy.json"
    path.write_text(json.dumps(data))

    try:
        categorize.load_taxonomy(path)
    except ValueError as exc:
        assert "class_map" in str(exc)
    else:
        raise AssertionError("missing class_map should raise ValueError")


def test_load_taxonomy_rejects_map_values_outside_categories(tmp_path):
    data = _load("taxonomy.json")
    data["tag_map"]["historic=castle"] = "not-a-category"
    path = tmp_path / "taxonomy.json"
    path.write_text(json.dumps(data))

    try:
        categorize.load_taxonomy(path)
    except ValueError as exc:
        assert "not-a-category" in str(exc)
    else:
        raise AssertionError("map values outside categories should raise ValueError")


def test_load_taxonomy_rejects_unknown_precedence_kind(tmp_path):
    data = _load("taxonomy.json")
    data["precedence"] = ["wd_p31", "unknown_kind"]
    path = tmp_path / "taxonomy.json"
    path.write_text(json.dumps(data))

    try:
        categorize.load_taxonomy(path)
    except ValueError as exc:
        assert "unknown_kind" in str(exc)
    else:
        raise AssertionError("unknown precedence kind should raise ValueError")

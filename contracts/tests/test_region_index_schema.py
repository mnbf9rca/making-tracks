import pytest

from mt_contracts import region_index
from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.versions import SCHEMA_VERSIONS


def _valid_index():
    return {
        "schema_version": SCHEMA_VERSIONS["region_index"],
        "min_reader_version": 1,
        "generated_at": "2026-07-17T12:00:00Z",
        "regions": [
            {
                "id": "malaysia-singapore-brunei",
                "display_name": "Malaysia",
                "parent": None,
                "bbox": [99.64, 0.85, 119.27, 7.36],
                "publish_version": "20260717T120000Z",
                "search_compact": {
                    "path": "malaysia-singapore-brunei/20260717T120000Z/search/compact.json",
                    "sha256": "1" * 64,
                    "bytes": 4096,
                    "schema_version": SCHEMA_VERSIONS["search_index"],
                },
                "basemap_bytes": 223155574,
                "tile_count": 12,
                "bytes_without_thumbs": 223456789,
                "bytes_with_thumbs": 223456789,
            },
            {
                "id": "malaysia-singapore-brunei_central",
                "display_name": "Central Malaysia",
                "parent": "malaysia-singapore-brunei",
                "bbox": [101.6, 3.0, 101.8, 3.2],
                "publish_version": "20260717T120000Z",
                "search_compact": {
                    "path": "malaysia-singapore-brunei_central/20260717T120000Z/search/compact.json",
                    "sha256": "2" * 64,
                    "bytes": 2048,
                    "schema_version": SCHEMA_VERSIONS["search_index"],
                },
                "basemap_bytes": 12345,
                "tile_count": 1,
                "bytes_without_thumbs": 13000,
                "bytes_with_thumbs": 13000,
            },
        ],
    }


def test_region_index_contract_allows_measured_uk_pack_with_thumbs_over_3gib():
    inst = _valid_index()
    inst["regions"][0]["bytes_with_thumbs"] = 3_578_585_075
    validate_instance("region-index", inst)


def test_region_index_schema_version_matches_registry():
    inst = _valid_index()
    assert inst["schema_version"] == SCHEMA_VERSIONS["region_index"]
    inst["schema_version"] = SCHEMA_VERSIONS["region_index"] - 1
    assert not is_valid("region-index", inst)


def test_region_index_contract_rejects_aggregate_pack_sizes_over_8gib():
    inst = _valid_index()
    inst["regions"][0]["bytes_with_thumbs"] = 8_589_934_593
    assert not is_valid("region-index", inst)


def test_region_index_contract_validates_parent_and_subregion_entries():
    inst = _valid_index()
    validate_instance("region-index", inst)
    region_index.validate_region_index(inst)


def test_region_index_contract_allows_future_min_reader_version():
    inst = _valid_index()
    inst["min_reader_version"] = 2
    validate_instance("region-index", inst)


def test_region_index_contract_rejects_unsafe_text_and_paths():
    inst = _valid_index()
    inst["regions"][0]["display_name"] = "Bad\u202eName"
    assert not is_valid("region-index", inst)

    inst = _valid_index()
    inst["regions"][0]["id"] = "../malaysia-singapore-brunei"
    assert not is_valid("region-index", inst)


def test_region_index_contract_rejects_bad_search_compact_path():
    inst = _valid_index()
    inst["regions"][0]["search_compact"]["path"] = "../search/compact.json"
    assert not is_valid("region-index", inst)


def test_region_index_contract_requires_search_compact_metadata():
    inst = _valid_index()
    del inst["regions"][0]["search_compact"]
    assert not is_valid("region-index", inst)


def test_region_index_helper_rejects_search_compact_version_mismatch():
    inst = _valid_index()
    inst["regions"][0]["search_compact"]["path"] = (
        "malaysia-singapore-brunei/20260718T120000Z/search/compact.json"
    )
    with pytest.raises(region_index.RegionIndexInvalid, match="search_compact path"):
        region_index.validate_region_index(inst)


def test_region_index_contract_rejects_invalid_latitude():
    inst = _valid_index()
    inst["regions"][0]["bbox"] = [99.64, 120, 119.27, 121]
    assert not is_valid("region-index", inst)


def test_region_index_helper_rejects_duplicate_region_ids():
    inst = _valid_index()
    inst["regions"][1]["id"] = "malaysia-singapore-brunei"
    with pytest.raises(region_index.RegionIndexInvalid, match="duplicate"):
        region_index.validate_region_index(inst)


def test_region_index_dedupe_prefers_highest_publish_version():
    records = [
        {"place_id": "mt1_same", "publish_version": "20260717T120000Z", "name": "old"},
        {"place_id": "mt1_other", "publish_version": "20260717T120000Z", "name": "other"},
        {"place_id": "mt1_same", "publish_version": "20260718T120000Z", "name": "new"},
    ]

    assert region_index.dedupe_places_by_publish_version(records) == [
        {"place_id": "mt1_other", "publish_version": "20260717T120000Z", "name": "other"},
        {"place_id": "mt1_same", "publish_version": "20260718T120000Z", "name": "new"},
    ]

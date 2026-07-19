from mt_contracts.search import split_shard_key_for_token
from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.versions import SCHEMA_VERSIONS


def _valid_search_index():
    return {
        "schema_version": SCHEMA_VERSIONS["search_index"],
        "min_reader_version": 1,
        "region": "malaysia-singapore-brunei",
        "publish_version": "20260719T100000Z",
        "generated_at": "2026-07-19T10:00:00Z",
        "index_kind": "full",
        "shard_key": "ke",
        "entries": [
            {
                "kind": "place",
                "place_id": "mt1_" + "0" * 26,
                "name": "Kellie's Castle",
                "alt_names": ["Istana Kellie", "吉利古堡"],
                "tokens": ["kellie", "castle", "istana", "吉利", "古堡"],
                "lat": 3.1,
                "lon": 101.7,
                "tier": 1,
                "category": "history",
            }
        ],
    }


def test_search_index_contract_pins_place_entry_shape():
    validate_instance("search-index", _valid_search_index())


def test_search_index_schema_version_matches_registry():
    inst = _valid_search_index()
    assert inst["schema_version"] == SCHEMA_VERSIONS["search_index"]
    inst["schema_version"] = SCHEMA_VERSIONS["search_index"] + 1
    assert not is_valid("search-index", inst)


def test_search_index_rejects_unsafe_text_and_bad_place_id():
    inst = _valid_search_index()
    inst["entries"][0]["name"] = "Bad\u202eName"
    assert not is_valid("search-index", inst)

    inst = _valid_search_index()
    inst["entries"][0]["place_id"] = "wd:Q42"
    assert not is_valid("search-index", inst)


def test_search_index_compact_has_no_prefix_shard_key():
    inst = _valid_search_index()
    inst["index_kind"] = "compact"
    inst["shard_key"] = None
    validate_instance("search-index", inst)

    inst["shard_key"] = "ke"
    assert not is_valid("search-index", inst)


def test_search_index_compact_rejects_tier_three_entries():
    inst = _valid_search_index()
    inst["index_kind"] = "compact"
    inst["shard_key"] = None
    inst["entries"][0]["tier"] = 3
    assert not is_valid("search-index", inst)


def test_search_index_rejects_full_index_without_prefix_shard_key():
    inst = _valid_search_index()
    inst["shard_key"] = None
    assert not is_valid("search-index", inst)


def test_search_index_rejects_entry_in_wrong_full_shard():
    inst = _valid_search_index()
    inst["shard_key"] = "zz"
    assert not is_valid("search-index", inst)


def test_search_index_accepts_split_full_shard_key():
    inst = _valid_search_index()
    inst["shard_key"] = split_shard_key_for_token(
        "kellie",
        inst["entries"][0]["place_id"],
    )
    validate_instance("search-index", inst)


def test_search_index_rejects_entry_in_wrong_split_full_shard():
    inst = _valid_search_index()
    inst["shard_key"] = "ke_x"
    assert not is_valid("search-index", inst)
